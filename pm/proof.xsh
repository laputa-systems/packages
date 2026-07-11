use elfdeps
use local
use pm.util as pm_util

export error ProofError = Failed(kind: Str, message: Str)

export proc ensure(condition: Bool, kind: Str, message: Str) [error] {
  if ! condition {
    return Err(ProofError.Failed(kind, message))
  }
}

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

export pure elf_machine_name(arch: Str) -> Str {
  if arch == "aarch64" {
    return "AArch64"
  }

  if arch == "x86_64" {
    return "X86-64"
  }

  return arch
}

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

export proc target_elf(root: Path, rel: Path, name: Str) [fs, process, env, error] {
  let path_value = fp"${root}/${rel}"
  ensure(fs.exists(path_value)?, f"proof-${name}", f"missing ELF: ${path_value.display()}")?
  let readelf = readelf_tool()?
  let header = run.text $readelf "-h" $path_value ?
  let arch = pm_util.target_arch()?
  ensure(header.contains(elf_machine_name(arch)), f"proof-${name}", f"${rel.display()} is not ${arch}")?
}
