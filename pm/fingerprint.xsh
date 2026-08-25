##! Exact semantic fingerprints for package inputs and executor identities.
use types
use util

pure canonical_field(value: Str) -> Str {
  value.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")
}

pure ignored_tree_path(rel: Path) -> Bool {
  let key = rel.display()
  key == ".git" or key.starts_with(".git/") or key == ".work" or key.starts_with(".work/") or key == "work" or key.starts_with("work/")
}

pure package_input_path(rel: Path) -> Bool {
  if ignored_tree_path(rel) or rel.name == "proof.xsh" {
    return false
  }

  let key = rel.display()
  rel.name.ends_with(".xsh") or key == "files" or key.starts_with("files/") or key == "patches" or key.starts_with("patches/")
}

proc tree_entry_line(root: Path, path_value: Path, prefix: Str) [fs, error] -> Result[Str] {
  let rel = path_value.strip_prefix(root)?
  let metadata = fs.metadata(path_value)?
  let label = canonical_field(rel.display())

  match metadata.kind {
    "file" => return f"${prefix}\tfile\t${label}\t${metadata.mode % 4096}\t${hash.sha256(path_value)?.hex()}"
    "symlink" => return f"${prefix}\tsymlink\t${label}\t${metadata.mode % 4096}\t${canonical_field(path_value.readlink()?.display())}"
    "dir" => return f"${prefix}\tdir\t${label}\t${metadata.mode % 4096}"
    _ => return f"${prefix}\t${metadata.kind}\t${label}\t${metadata.mode % 4096}\t${metadata.size}"
  }
}

proc digest_lines(lines: List[Str]) [error] -> Result[Str] {
  bytes.from_text((lines |> sort).join("\n") + "\n").sha256().hex()
}

pure applicable_aarch64_checksum(source: types.UpstreamSource) -> Str {
  var all_checksum = ""

  for checksum in source.checksums {
    if checksum.arch == "aarch64" {
      return checksum.sha256
    }

    if checksum.arch == "all" {
      all_checksum = checksum.sha256
    }
  }

  all_checksum
}

proc package_source_lines(pkg: types.Package) [fs, error] -> Result[List[Str]] {
  var lines: List[Str] = []

  for entry in fs.walk(pkg.dir) |> sort-by .path {
    let rel = entry.path.strip_prefix(pkg.dir)?

    if package_input_path(rel) {
      lines = lines.push(tree_entry_line(pkg.dir, entry.path, "package-file")?)
    }
  }

  lines
}

## Hashes every semantic package build input without absolute checkout state or modification times.
export proc package_build_input(
  repo_root: Path,
  pkg: types.Package,
  target: types.Target,
) [fs, error] -> Result[Str] {
  let _ = repo_root
  var lines = [
    "format\tlaputa-package-build-input-1",
    f"package\t${canonical_field(pkg.name)}\t${canonical_field(pkg.ver)}\t${canonical_field(pkg.rel)}",
    f"package-kind\t${types.package_kind_text(pkg.kind)}",
    f"target\t${types.target_text(target)}",
    f"nostrip\t${pkg.nostrip}",
    f"source-mirror\t${pkg.source_mirror}",
  ]

  for dependency in pkg.deps {
    lines = lines.push(f"dependency\t${types.dependency_kind_text(types.Runtime)}\t${canonical_field(dependency)}")
  }

  for dependency in pkg.mkdeps_host {
    lines = lines.push(f"dependency\t${types.dependency_kind_text(types.BuildHost)}\t${canonical_field(dependency)}")
  }

  for dependency in pkg.mkdeps_target {
    lines = lines.push(f"dependency\t${types.dependency_kind_text(types.BuildTarget)}\t${canonical_field(dependency)}")
  }

  for source in pkg.upstream_sources {
    lines = lines.push(
      f"source\t${canonical_field(source.source.display())}\t${types.source_kind_text(source.kind)}\t${canonical_field(applicable_aarch64_checksum(source))}",
    )
  }

  for entry in pkg.filetree {
    lines = lines.push(f"filetree\t${canonical_field(entry.path.display())}\t${types.file_kind_text(entry.kind)}")
  }

  lines = lines.extend(package_source_lines(pkg)?)
  digest_lines(lines)?
}

proc pm_proof_module(pm_root: Path) [fs, error] -> Result[Str] {
  let proof = fp"${pm_root}/pm/proof.xsh"

  if ! fs.exists(proof)? {
    return Err(types.PmError.PackageContract(f"${proof.display()} is missing"))
  }

  hash.sha256(proof)?.hex()
}

## Hashes proof-only inputs independently from build inputs so an unchanged artifact can be re-proved.
export proc package_proof_input(repo_root: Path, pkg: types.Package) [fs, error] -> Result[Str] {
  let proof = fp"${pkg.dir}/proof.xsh"
  let proof_sha256 = if fs.exists(proof)? { hash.sha256(proof)?.hex() } else { "missing" }
  digest_lines([
    "format\tlaputa-package-proof-input-1",
    f"package\t${canonical_field(util.package_id(pkg.name, pkg.ver, pkg.rel))}",
    f"proof\t${proof_sha256}",
    f"pm-proof\t${pm_proof_module(repo_root)?}",
  ])?
}

## Hashes the PM entrypoint and every implementation module below `pm/`.
export proc pm_tree(pm_root: Path) [fs, error] -> Result[Str] {
  let entrypoint = fp"${pm_root}/pm.xsh"
  let modules = fp"${pm_root}/pm"

  if ! fs.exists(entrypoint)? or ! fs.exists(modules)? {
    return Err(types.PmError.PackageContract(f"${pm_root.display()} is not a PM source root"))
  }

  var lines = ["format\tlaputa-pm-tree-1", tree_entry_line(pm_root, entrypoint, "pm")?]

  for entry in fs.walk(modules) |> sort-by .path {
    let rel = entry.path.strip_prefix(pm_root)?

    if ! ignored_tree_path(rel) and entry.kind != "dir" and entry.path.name.ends_with(".xsh") {
      lines = lines.push(tree_entry_line(pm_root, entry.path, "pm")?)
    }
  }

  digest_lines(lines)?
}

## Hashes mounted XSH core applets by relative path, mode, and contents.
export proc core_tree(core_root: Path) [fs, error] -> Result[Str] {
  if ! fs.exists(core_root)? {
    return Err(types.PmError.PackageContract(f"${core_root.display()} is missing"))
  }

  var lines = ["format\tlaputa-core-tree-1"]

  for entry in fs.walk(core_root) |> sort-by .path {
    let rel = entry.path.strip_prefix(core_root)?

    if ! ignored_tree_path(rel) and rel.display() != "" {
      lines = lines.push(tree_entry_line(core_root, entry.path, "core")?)
    }
  }

  digest_lines(lines)?
}

## Hashes the three Linux XSH runner binaries under the executor identity format.
export proc runners(xsh: Path, xshi: Path, xsht: Path) [fs, error] -> Result[Str] {
  digest_lines([
    "format\tlaputa-pm-executor-1",
    f"runner\txsh\t${hash.sha256(xsh)?.hex()}",
    f"runner\txshi\t${hash.sha256(xshi)?.hex()}",
    f"runner\txsht\t${hash.sha256(xsht)?.hex()}",
  ])?
}
