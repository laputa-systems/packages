##! PM util operations and shared package-manager policy.
use types

## Exported PM declaration `package_id`.
export pure package_id(name: Str, ver: Str, rel: Str) -> Str {
  f"${name}-${ver}-${rel}"
}

## Exported PM declaration `package_arch_id`.
export pure package_arch_id(arch: Str, name: Str, ver: Str, rel: Str) -> Str {
  f"${arch}/${package_id(name, ver, rel)}"
}

## Exported PM declaration `version_id`.
export pure version_id(ver: Str, rel: Str) -> Str {
  f"${ver}-${rel}"
}

## Exported PM declaration `packages_db_path`.
export pure packages_db_path(root: Path) -> Path {
  fp"${root}/var/lib/xsh-pm/packages"
}

## Exported PM declaration `package_db_path`.
export pure package_db_path(root: Path, name: Str) -> Path {
  fp"${packages_db_path(root)}/${name}"
}

## Exported PM declaration `auth_token_path`.
export pure auth_token_path(root: Path) -> Path {
  fp"${root}/var/lib/xsh-pm/auth/token"
}

## Exported PM declaration `remote_index_cache_path`.
export pure remote_index_cache_path(out: Path) -> Path {
  fp"${out}/remote-index.json"
}

## Exported PM declaration `source_mirror_path_for_arch`.
export pure source_mirror_path_for_arch(out: Path, pkg: types.Package, arch: Str) -> Path {
  fp"${out}/source-mirrors/${package_id(pkg.name, pkg.ver, pkg.rel)}-${arch}.tar.bz2"
}

## Exported PM declaration `source_manifest_path_for_arch`.
export pure source_manifest_path_for_arch(out: Path, pkg: types.Package, arch: Str) -> Path {
  fp"${out}/source-mirrors/${package_id(pkg.name, pkg.ver, pkg.rel)}-${arch}.manifest.json"
}

## Exported PM declaration `proof_receipt_path`.
export pure proof_receipt_path(out: Path, pkg: types.Package) -> Path {
  fp"${out}/${package_id(pkg.name, pkg.ver, pkg.rel)}.proof.json"
}

## Exported PM declaration `remote_tarball_name`.
export pure remote_tarball_name(name: Str, ver: Str, rel: Str) -> Str {
  f"${package_id(name, ver, rel)}.tar.gz"
}

## Exported PM declaration `remote_source_name_for_arch`.
export pure remote_source_name_for_arch(name: Str, ver: Str, rel: Str, arch: Str) -> Str {
  f"${package_id(name, ver, rel)}-${arch}-src.tar.bz2"
}

## Exported PM declaration `remote_binary_rel`.
export pure remote_binary_rel(arch: Str, name: Str, ver: Str, rel: Str) -> Path {
  fp"packages/${arch}/${name}/${remote_tarball_name(name, ver, rel)}"
}

## Exported PM declaration `remote_metadata_name`.
export pure remote_metadata_name(name: Str, ver: Str, rel: Str) -> Str {
  f"${package_id(name, ver, rel)}.json"
}

## Exported PM declaration `remote_metadata_rel`.
export pure remote_metadata_rel(arch: Str, name: Str, ver: Str, rel: Str) -> Path {
  fp"metadata/${arch}/${name}/${remote_metadata_name(name, ver, rel)}"
}

## Exported PM declaration `remote_source_rel_for_arch`.
export pure remote_source_rel_for_arch(arch: Str, name: Str, ver: Str, rel: Str) -> Path {
  fp"sources/${name}/${remote_source_name_for_arch(name, ver, rel, arch)}"
}

## Exported PM declaration `ensure_relative_path`.
export pure ensure_relative_path(path_value: Path, label: Str) -> Result[Path] {
  let normalized = path_value.normalize()
  let text = normalized.display()

  if text.starts_with("/") {
    return Err(types.PmError.SourceDestination(f"${label} must stay relative: ${path_value.display()}"))
  }

  for component in text.split("/") {
    if component == ".." {
      return Err(types.PmError.SourceDestination(f"${label} must stay relative: ${path_value.display()}"))
    }
  }

  normalized
}

## Exported PM declaration `remote_cache_tarball_path`.
export pure remote_cache_tarball_path(out: Path, pkg: types.RemotePackage) -> Result[Path] {
  if pkg.tarball != "" {
    let rel = ensure_relative_path(fp"${pkg.tarball}", "remote tarball")?
    return fp"${out}/remote-cache/${rel}"
  }

  fp"${out}/remote-cache/${pkg.arch}/${pkg.name}/${remote_tarball_name(pkg.name, pkg.ver, pkg.rel)}"
}

## Exported PM declaration `remote_cache_metadata_path`.
export pure remote_cache_metadata_path(out: Path, pkg: types.RemotePackage) -> Result[Path] {
  if pkg.metadata != "" {
    let rel = ensure_relative_path(fp"${pkg.metadata}", "remote metadata")?
    return fp"${out}/remote-cache/${rel}"
  }

  fp"${out}/remote-cache/${pkg.arch}/${pkg.name}/${remote_metadata_name(pkg.name, pkg.ver, pkg.rel)}"
}

## Exported PM declaration `is_file_url`.
export pure is_file_url(url: Str) -> Bool {
  url.starts_with("file://")
}

## Exported PM declaration `file_url_path`.
export pure file_url_path(url: Str) -> Result[Path] {
  fp"${url.replace("file://", "")}"
}

## Exported PM declaration `repo_file_path`.
export pure repo_file_path(repo: Str, rel: Path) -> Result[Path] {
  fp"${file_url_path(repo)?}/${ensure_relative_path(rel, "repo path")?}"
}

## Exported PM declaration `repo_url_for`.
export pure repo_url_for(repo: Str, rel: Path) -> Result[Str] {
  f"${repo}/${ensure_relative_path(rel, "repo path")?.display()}"
}

## Exported PM declaration `is_tar_source`.
export pure is_tar_source(candidate: Path) -> Bool {
  let name = candidate.name

  name.ends_with(".tar") or name.ends_with(".tar.gz") or name.ends_with(".tgz") or name.ends_with(".tar.bz2") or name.ends_with(
    ".tbz2",
  ) or name.ends_with(".tar.xz") or name.ends_with(".txz") or name.ends_with(".tar.lzma") or name.ends_with(".crate")
}

## Exported PM declaration `is_zip_source`.
export pure is_zip_source(candidate: Path) -> Bool {
  candidate.name.ends_with(".zip")
}

## Exported PM declaration `is_cpio_source`.
export pure is_cpio_source(candidate: Path) -> Bool {
  candidate.name.ends_with(".cpio")
}

## Exported PM declaration `is_etc_file`.
export pure is_etc_file(candidate: Path) -> Bool {
  candidate.display().starts_with("etc/")
}

## Exported PM declaration `is_url_source`.
export pure is_url_source(source: Str) -> Bool {
  "://" in source
}

## Exported PM declaration `is_git_source`.
export pure is_git_source(source: Str) -> Bool {
  source.starts_with("git+")
}

## Exported PM declaration `git_source_body`.
export pure git_source_body(source: Str) -> Str {
  if source.starts_with("git+") {
    return source.replace("git+", "")
  }

  return source
}

## Exported PM declaration `git_source_url`.
export pure git_source_url(source: Str) -> Str {
  let body = git_source_body(source)
  let hash_parts = body.split("#")
  let before_hash = hash_parts[0]
  let at_parts = before_hash.split("@")
  return at_parts[0]
}

## Exported PM declaration `git_source_ref`.
export pure git_source_ref(source: Str) -> Str {
  let body = git_source_body(source)
  let hash_parts = body.split("#")

  if hash_parts.len() > 1 {
    return hash_parts[1]
  }

  let at_parts = body.split("@")

  if at_parts.len() > 1 {
    return at_parts[1]
  }

  return ""
}

## Exported PM declaration `strip_git_ext`.
export pure strip_git_ext(name: Str) -> Str {
  if name.ends_with(".git") {
    return name.split(".git")[0]
  }

  return name
}

## Exported PM declaration `source_basename`.
export pure source_basename(source: Str) -> Result[Str] {
  if source.starts_with("git+") {
    let parsed_path = fp"${git_source_url(source)}"
    return strip_git_ext(parsed_path.name)
  }

  let parsed_path = fp"${source.split("#")[0].split("?")[0]}"
  return parsed_path.name
}

## Exported PM declaration `parse_source_line`.
export pure parse_source_line(raw: Path) -> Result[types.SourceLine] {
  let raw_text = raw.display()
  let spaced = raw_text.split(" => ")

  if spaced.len() > 1 {
    return {source: spaced[0].trim(), dest: fp"${spaced[1].trim()}"}
  }

  let tight = raw_text.split("=>")

  if tight.len() > 1 {
    return {source: tight[0].trim(), dest: fp"${tight[1].trim()}"}
  }

  return {source: raw_text, dest: p"."}
}

## Exported PM declaration `source_stage_dir`.
export pure source_stage_dir(src: Path, line: types.SourceLine) -> Path {
  let dest = line.dest.normalize()

  if dest.display() == "." {
    return src
  }

  return fp"${src}/${dest}"
}

## Exported PM declaration `source_cache_path`.
export pure source_cache_path(work: Path, pkg: types.Package, line: types.SourceLine, source: Str) -> Result[Path] {
  let name = source_basename(source)?
  let root = fp"${work}/sources/${pkg.name}"
  let dest = line.dest.normalize()

  if dest.display() == "." {
    return fp"${root}/${name}"
  }

  return fp"${root}/${dest}/${name}"
}

## Exported PM declaration `goarch_for`.
export pure goarch_for(arch: Str) -> Str {
  if arch == "aarch64" or arch == "arm64" {
    return "arm64"
  }

  if arch == "x86_64" {
    return "amd64"
  }

  return arch
}

## Exported PM declaration `source_vars`.
export proc source_vars(source: Str, pkg: types.Package, arch: Str) [env, error] -> Result[Str] {
  let version = pkg.ver.replace("+", ".").replace("-", ".").replace("_", ".")
  let parts = version.split(".")
  let major = parts.get(0, "")
  let minor = parts.get(1, "")
  let patch_part = parts.get(2, "")
  let ident = parts.get(3, "")
  let goarch = goarch_for(arch)
  let build = build_arch()?
  let build_goarch = goarch_for(build)
  let source_target_triple = f"${arch}-linux-musl"
  let source_build_triple = f"${build}-linux-musl"
  var expanded = source
  expanded = expanded.replace("VERSION", pkg.ver)
  expanded = expanded.replace("RELEASE", pkg.rel)
  expanded = expanded.replace("MAJOR", major)
  expanded = expanded.replace("MINOR", minor)
  expanded = expanded.replace("PATCH", patch_part)
  expanded = expanded.replace("IDENT", ident)
  expanded = expanded.replace("PACKAGE", pkg.name)
  expanded = expanded.replace("TARGET_TRIPLE", source_target_triple)
  expanded = expanded.replace("BUILD_TRIPLE", source_build_triple)
  expanded = expanded.replace("TARGET_GOARCH", goarch)
  expanded = expanded.replace("BUILD_GOARCH", build_goarch)
  expanded = expanded.replace("TARGET_ARCH", arch)
  expanded = expanded.replace("BUILD_ARCH", build)
  expanded = expanded.replace("GOARCH", goarch)
  expanded.replace("ARCH", arch)
}

## Exported PM declaration `paths_from_args`.
export proc paths_from_args(raw: List[Str]) [error] -> Result[List[Path]] {
  let paths = [fp"${item}" for item in raw]
  paths
}

## Exported PM declaration `host_arch`.
export proc host_arch() [env, error] -> Result[Str] {
  let os = system.uname()?
  normalize_arch(os.machine)
}

## Exported PM declaration `build_arch`.
export proc build_arch() [env, error] -> Result[Str] {
  let override = (env.get("XSH_PM_BUILD_ARCH") ?? "").trim()

  if override != "" {
    return normalize_arch(override)
  }

  host_arch()?
}

## Exported PM declaration `target_arch`.
export proc target_arch() [env, error] -> Result[Str] {
  let target_override = (env.get("XSH_PM_TARGET_ARCH") ?? "").trim()

  if target_override != "" {
    return normalize_arch(target_override)
  }

  let legacy_override = (env.get("XSH_PM_ARCH") ?? "").trim()

  if legacy_override != "" {
    return normalize_arch(legacy_override)
  }

  host_arch()?
}

## Exported PM declaration `machine_arch`.
export proc machine_arch() [env, error] -> Result[Str] {
  target_arch()?
}

## Exported PM declaration `target_triple`.
export proc target_triple() [env, error] -> Result[Str] {
  let arch = target_arch()?
  return f"${arch}-linux-musl"
}

## Exported PM declaration `normalize_arch`.
export pure normalize_arch(arch: Str) -> Str {
  if arch == "arm64" {
    return "aarch64"
  }

  if arch == "amd64" {
    return "x86_64"
  }

  arch
}
