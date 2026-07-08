use types

export pure package_id(name: Str, ver: Str, rel: Str) -> Str {
  f"${name}-${ver}-${rel}"
}

export pure package_arch_id(arch: Str, name: Str, ver: Str, rel: Str) -> Str {
  f"${arch}/${package_id(name, ver, rel)}"
}

export pure version_id(ver: Str, rel: Str) -> Str {
  f"${ver}-${rel}"
}

export pure packages_db_path(root: Path) -> Path {
  fp"${root}/var/lib/xsh-pm/packages"
}

export pure package_db_path(root: Path, name: Str) -> Path {
  fp"${packages_db_path(root)}/${name}"
}

export pure auth_token_path(root: Path) -> Path {
  fp"${root}/var/lib/xsh-pm/auth/token"
}

export pure remote_index_cache_path(out: Path) -> Path {
  fp"${out}/remote-index.json"
}

export pure source_mirror_path_for_arch(out: Path, pkg: Package, arch: Str) -> Path {
  fp"${out}/source-mirrors/${package_id(pkg.name, pkg.ver, pkg.rel)}-${arch}.tar.gz"
}

export pure remote_tarball_name(name: Str, ver: Str, rel: Str) -> Str {
  f"${package_id(name, ver, rel)}.tar.gz"
}

export pure remote_source_tarball_name_for_arch(name: Str, ver: Str, rel: Str, arch: Str) -> Str {
  f"${package_id(name, ver, rel)}-${arch}-src.tar.gz"
}

export pure remote_binary_rel(arch: Str, name: Str, ver: Str, rel: Str) -> Path {
  fp"packages/${arch}/${name}/${remote_tarball_name(name, ver, rel)}"
}

export pure remote_metadata_name(name: Str, ver: Str, rel: Str) -> Str {
  f"${package_id(name, ver, rel)}.json"
}

export pure remote_metadata_rel(arch: Str, name: Str, ver: Str, rel: Str) -> Path {
  fp"metadata/${arch}/${name}/${remote_metadata_name(name, ver, rel)}"
}

export pure remote_source_rel_for_arch(arch: Str, name: Str, ver: Str, rel: Str) -> Path {
  fp"sources/${name}/${remote_source_tarball_name_for_arch(name, ver, rel, arch)}"
}

export pure ensure_relative_path(path_value: Path, label: Str) -> Result[Path] {
  let normalized = path_value.normalize()
  let text = normalized.display()

  if text.starts_with("/") {
    return Err(PmError.SourceDestination(f"${label} must stay relative: ${path_value.display()}"))
  }

  for component in text.split("/") {
    if component == ".." {
      return Err(PmError.SourceDestination(f"${label} must stay relative: ${path_value.display()}"))
    }
  }

  normalized
}

export pure remote_cache_tarball_path(out: Path, pkg: RemotePackage) -> Result[Path] {
  if pkg.tarball != "" {
    let rel = ensure_relative_path(fp"${pkg.tarball}", "remote tarball")?
    return fp"${out}/remote-cache/${rel}"
  }

  fp"${out}/remote-cache/${pkg.arch}/${pkg.name}/${remote_tarball_name(pkg.name, pkg.ver, pkg.rel)}"
}

export pure remote_cache_metadata_path(out: Path, pkg: RemotePackage) -> Result[Path] {
  if pkg.metadata != "" {
    let rel = ensure_relative_path(fp"${pkg.metadata}", "remote metadata")?
    return fp"${out}/remote-cache/${rel}"
  }

  fp"${out}/remote-cache/${pkg.arch}/${pkg.name}/${remote_metadata_name(pkg.name, pkg.ver, pkg.rel)}"
}

export pure is_file_url(url: Str) -> Bool {
  url.starts_with("file://")
}

export pure file_url_path(url: Str) -> Result[Path] {
  fp"${url.replace("file://", "")}"
}

export pure repo_file_path(repo: Str, rel: Path) -> Result[Path] {
  fp"${file_url_path(repo)?}/${ensure_relative_path(rel, "repo path")?}"
}

export pure repo_url_for(repo: Str, rel: Path) -> Result[Str] {
  f"${repo}/${ensure_relative_path(rel, "repo path")?.display()}"
}

export pure is_tar_source(candidate: Path) -> Bool {
  let name = candidate.name

  name.ends_with(".tar") or name.ends_with(".tar.gz") or name.ends_with(".tgz") or name.ends_with(".tar.bz2") or name.ends_with(
    ".tbz2",
  ) or name.ends_with(".tar.xz") or name.ends_with(".txz") or name.ends_with(".tar.lzma") or name.ends_with(".crate")
}

export pure is_zip_source(candidate: Path) -> Bool {
  candidate.name.ends_with(".zip")
}

export pure is_cpio_source(candidate: Path) -> Bool {
  candidate.name.ends_with(".cpio")
}

export pure is_etc_file(candidate: Path) -> Bool {
  candidate.display().starts_with("etc/")
}

export pure is_url_source(source: Str) -> Bool {
  "://" in source
}

export pure is_git_source(source: Str) -> Bool {
  source.starts_with("git+")
}

export pure git_source_body(source: Str) -> Str {
  if source.starts_with("git+") {
    return source.replace("git+", "")
  }

  return source
}

export pure git_source_url(source: Str) -> Str {
  let body = git_source_body(source)
  let hash_parts = body.split("#")
  let before_hash = hash_parts[0]
  let at_parts = before_hash.split("@")
  return at_parts[0]
}

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

export pure strip_git_ext(name: Str) -> Str {
  if name.ends_with(".git") {
    return name.split(".git")[0]
  }

  return name
}

export pure source_basename(source: Str) -> Result[Str] {
  if source.starts_with("git+") {
    let parsed_path = fp"${git_source_url(source)}"
    return strip_git_ext(parsed_path.name)
  }

  let parsed_path = fp"${source.split("#")[0].split("?")[0]}"
  return parsed_path.name
}

export pure parse_source_line(raw: Path) -> Result[SourceLine] {
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

export pure source_stage_dir(src: Path, line: SourceLine) -> Path {
  let dest = line.dest.normalize()

  if dest.display() == "." {
    return src
  }

  return fp"${src}/${dest}"
}

export pure source_cache_path(work: Path, pkg: Package, line: SourceLine, source: Str) -> Result[Path] {
  let name = source_basename(source)?
  let root = fp"${work}/sources/${pkg.name}"
  let dest = line.dest.normalize()

  if dest.display() == "." {
    return fp"${root}/${name}"
  }

  return fp"${root}/${dest}/${name}"
}

export pure goarch_for(arch: Str) -> Str {
  if arch == "aarch64" or arch == "arm64" {
    return "arm64"
  }

  if arch == "x86_64" {
    return "amd64"
  }

  return arch
}

export pure source_vars(source: Str, pkg: Package, arch: Str) -> Str {
  let version = pkg.ver.replace("+", ".").replace("-", ".").replace("_", ".")
  let parts = version.split(".")
  let major: Str = parts.get(0, "")
  let minor: Str = parts.get(1, "")
  let patch_part: Str = parts.get(2, "")
  let ident: Str = parts.get(3, "")
  let goarch = goarch_for(arch)

  return source.replace("VERSION", pkg.ver).replace("RELEASE", pkg.rel).replace("MAJOR", major).replace("MINOR", minor).replace(
    "PATCH",
    patch_part,
  ).replace("IDENT", ident).replace("PACKAGE", pkg.name).replace("GOARCH", goarch).replace("ARCH", arch)
}

export pure checksum_field_line(line: Str, field: Str) -> Bool {
  line.starts_with(f"export let ${field} ") or line.starts_with(f"export let ${field}:") or line.starts_with(
    f"export let ${field}=",
  ) or line.starts_with(f"let ${field} ") or line.starts_with(f"let ${field}:") or line.starts_with(f"let ${field}=")
}

export proc paths_from_args(raw: List[Str]) [error] -> Result[List[Path]] {
  let paths = [fp"${item}" for item in raw]
  paths
}

export proc host_arch() [env, error] -> Result[Str] {
  let os = system.uname()?
  normalize_arch(os.machine)
}

export proc build_arch() [env, error] -> Result[Str] {
  let override = (env.get("XSH_PM_BUILD_ARCH") ?? "").trim()

  if override != "" {
    return normalize_arch(override)
  }

  host_arch()?
}

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

export proc machine_arch() [env, error] -> Result[Str] {
  target_arch()?
}

export proc target_triple() [env, error] -> Result[Str] {
  let arch = target_arch()?
  return f"${arch}-linux-musl"
}

export pure normalize_arch(arch: Str) -> Str {
  if arch == "arm64" {
    return "aarch64"
  }

  if arch == "amd64" {
    return "x86_64"
  }

  arch
}
