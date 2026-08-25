##! PM proof operations and shared package-manager policy.
use elfdeps
use local
use pm.util as pm_util
use types

type ArtifactProofDto = {
  format: Str,
  package_id: Str,
  artifact_key: Str,
  proof_key: Str,
  proof_sha256: Str,
  payload_sha256: Str,
}

## Exported PM declaration `ProofError`.
export error ProofError = Failed(kind: Str, message: Str)

## Exported PM declaration `ensure`.
export proc ensure(condition: Bool, kind: Str, message: Str) [error] {
  if ! condition {
    return Err(ProofError.Failed(kind, message))
  }
}

## Exported PM declaration `package_metadata`.
export proc package_metadata(root: Path, name: Str) [fs, error] {
  let db = fp"${root}/var/lib/xsh-pm/packages/${name}/metadata.json"
  ensure(fs.exists(db)?, f"proof-${name}", f"missing package metadata: ${db.display()}")?
}

proc package_dependency_map(root: Path) [fs, error] -> Result[Map[List[Str]]] {
  var package_deps: Map[List[Str]] = {}
  let packages_db = fp"${root}/var/lib/xsh-pm/packages"

  if ! fs.exists(packages_db)? {
    return package_deps
  }

  for entry in fs.children(packages_db) |> where .kind == "dir" {
    let metadata_path = fp"${entry.path}/metadata.json"

    if fs.exists(metadata_path)? {
      let metadata: Record = json.read(metadata_path)?
      var deps: List[Str] = []

      if metadata.has("deps") {
        deps = metadata.get("deps")?
      }

      package_deps[entry.name] = deps
    }
  }

  package_deps
}

## Exported PM declaration `verify_package_elf_dependencies`.
export proc verify_package_elf_dependencies(root: Path, name: Str) [fs, error] {
  let providers = elfdeps.collect_library_providers(root)?
  let package_deps = package_dependency_map(root)?
  let allowed = elfdeps.runtime_dependency_closure(package_deps.get(name, []), package_deps)
  let manifest = local.load_manifest(fp"${root}/var/lib/xsh-pm/packages/${name}")?
  var failures = []

  for rel_path in manifest {
    let path_value = fp"${root}/${rel_path}"

    if path_value.exists()? {
      failures = failures.extend(
        elfdeps.installed_file_elf_dependency_failures(name, allowed, rel_path, path_value, providers)?,
      )
    }
  }

  if failures.len() > 0 {
    let first = failures[0]

    return Err(
      ProofError.Failed(
        f"proof-${name}",
        f"${first.file.display()} needs ${first.soname} from ${first.provider} without a runtime dependency",
      ),
    )
  }
}

## Exported PM declaration `elf_machine_name`.
export pure elf_machine_name(arch: Str) -> Str {
  if arch == "aarch64" {
    return "AArch64"
  }

  if arch == "x86_64" {
    return "X86-64"
  }

  return arch
}

## Exported PM declaration `readelf_tool`.
export proc readelf_tool() [fs, process, env, error] -> Result[Path] {
  let host_readelf = /usr/bin/readelf
  let host_llvm_readelf = /usr/bin/llvm-readelf

  if fs.exists(host_readelf)? {
    return host_readelf
  }

  if fs.exists(host_llvm_readelf)? {
    return host_llvm_readelf
  }

  match process.which("readelf") {
    Ok(tool) => return tool
    Err(_) => {}
  }

  return process.which("llvm-readelf")?
}

## Exported PM declaration `target_elf`.
export proc target_elf(root: Path, rel: Path, name: Str) [fs, process, env, error] {
  let path_value = fp"${root}/${rel}"
  ensure(fs.exists(path_value)?, f"proof-${name}", f"missing ELF: ${path_value.display()}")?
  let readelf = readelf_tool()?
  let header = run.text $readelf "-h" $path_value ?
  let arch = pm_util.target_arch()?
  ensure(header.contains(elf_machine_name(arch)), f"proof-${name}", f"${rel.display()} is not ${arch}")?
}

proc proof_xsh_runner() [fs, process, env, error] -> Result[Path] {
  let configured = (env.get("XSH_HOST") ?? "").trim()

  if configured != "" {
    let selected = fp"${configured}"

    if fs.exists(selected)? {
      return selected
    }
  }

  if fs.exists(/bin/xsh)? {
    return /bin/xsh
  }

  process.which("xsh")?
}

## Runs one package proof against an already composed mutable proof work root.
## Callers must seed the explicit executor substrate before invoking this boundary.
export proc run_artifact_proof(root: Path, pkg: types.Package) [fs, process, env, error] {
  let script = fp"${pkg.dir}/proof.xsh"

  if ! fs.exists(script)? {
    return Err(types.PmError.PackageContract(f"${pkg.name} is missing proof.xsh"))
  }

  package_metadata(root, pkg.name)?
  verify_package_elf_dependencies(root, pkg.name)?
  let xsh = proof_xsh_runner()?

  env {
    LAPUTA_ROOT = root.display()
    PATH = f"${root}/bin:${root}/usr/bin:${env.get("PATH") ?? ""}"
    XSH_MODULE_PATH = env.get("XSH_MODULE_PATH") ?? ""
    XSH_PM_PROOF_ROOT = root.display()
    XSH_PM_PROOF_HOST_PATH = env.get("PATH") ?? ""
    SHELL = fp"${root}/bin/xshi"
  } {
    let status = process.run(process.command_argv(xsh, [xsh.display(), script.display(), "--", root.display()]))?

    if ! status.ok {
      if status.exited() {
        return Err(types.PmError.ExtensionFailed(f"package proof for ${pkg.name} exited with status ${status.exit_code()?}"))
      }

      return Err(types.PmError.ExtensionFailed(f"package proof for ${pkg.name} was signaled"))
    }
  } ?
}

## Writes the deterministic proof receipt that binds a proof input to one exact payload artifact.
export proc write_artifact_receipt(path_value: Path, node: types.PlanNode, payload: Path) [fs, error] {
  fs.mkdir(path_value.parent)?
  fs.write(
    path_value,
    json.encode({
      format: "laputa-package-proof-3",
      package_id: node.package_id,
      artifact_key: node.artifact_key,
      proof_key: node.proof_key,
      proof_sha256: node.proof_sha256,
      payload_sha256: hash.sha256(payload)?.hex(),
    })? + "\n",
  )?
}

## Verifies an immutable proof receipt against the exact node and payload it attests.
export proc verify_artifact_receipt(path_value: Path, node: types.PlanNode, payload: Path) [fs, error] {
  let value = json.read(path_value)?.require(ArtifactProofDto)?

  if value.format != "laputa-package-proof-3" {
    return Err(types.PmError.PackageContract(f"unsupported package proof format ${value.format}"))
  }

  if value.package_id != node.package_id or value.artifact_key != node.artifact_key or value.proof_key != node.proof_key or value.proof_sha256 != node.proof_sha256 {
    return Err(types.PmError.PackageContract(f"proof receipt ${path_value.display()} does not match ${node.package_id}"))
  }

  if value.payload_sha256 != hash.sha256(payload)?.hex() {
    return Err(types.PmError.PackageContract(f"proof receipt ${path_value.display()} payload hash does not match ${node.package_id}"))
  }
}
