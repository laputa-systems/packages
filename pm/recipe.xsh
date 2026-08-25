##! Typed package-recipe loading and dynamic procedure invocation. This is the sole boundary that reads dynamic `PKGBUILD.xsh` exports; all callers receive `types.Package` records and use its call helpers rather than retaining dynamic module values.
use types
use util

type PackageMetadata = {
  name: Str,
  ver: Str,
  rel: Str,
  deps: List[Str],
  mkdeps_host: List[Str],
  mkdeps_target: List[Str],
  upstream_sources: List[Record],
  filetree: List[Record],
  filetree_aarch64: List[Record],
  has_filetree_aarch64: Bool,
  filetree_x86_64: List[Record],
  has_filetree_x86_64: Bool,
  has_build: Bool,
  package_kind: Str,
  has_package_kind: Bool,
  nostrip: Bool,
  source_mirror: Bool,
}

proc package_contract_error(pkg: Str, message: Str) [error] -> Result[Unit] {
  return Err(types.PmError.PackageContract(f"${pkg}: ${message}"))
}

proc validate_package_name(name: Str) [error] -> Result[Unit] {
  let pattern = regex.compile("^[a-z0-9][a-z0-9+._-]*$")?

  if ! pattern.matches(name) {
    return package_contract_error(name, "name must match [a-z0-9][a-z0-9+._-]*")
  }
}

proc validate_positive_release(name: Str, rel: Str) [error] -> Result[Unit] {
  let pattern = regex.compile("^[1-9][0-9]*$")?

  if ! pattern.matches(rel) {
    return package_contract_error(name, "rel must be a positive decimal string")
  }
}

proc validate_dependencies(name: Str, label: Str, dependencies: List[Str]) [error] -> Result[Unit] {
  var seen: Map[Bool] = {}

  for dependency in dependencies {
    if seen.has(dependency) {
      return package_contract_error(name, f"${label} contains duplicate dependency ${dependency}")
    }

    if dependency == name {
      return package_contract_error(name, f"${label} may not depend on itself")
    }

    seen[dependency] = true
  }
}

proc source_is_repository_local(source: Path) [] -> Bool {
  let raw = source.display()
  return ! util.is_url_source(raw) and ! util.is_git_source(raw) and ! raw.starts_with("/")
}

proc decode_source_checksum(name: Str, raw: Record) [error] -> Result[types.SourceChecksum] {
  let arch: Str = raw.get("arch")?
  let sha256: Str = raw.get("sha256")?

  if arch != "aarch64" and arch != "all" and arch != "x86_64" {
    return Err(types.PmError.PackageContract(f"${name}: checksum has invalid architecture ${arch}"))
  }

  if sha256 == "" {
    return Err(types.PmError.PackageContract(f"${name}: checksum for ${arch} is empty"))
  }

  {arch, sha256}
}

proc decode_upstream_source(name: Str, raw: Record) [error] -> Result[types.UpstreamSource] {
  let source: Path = raw.get("source")?
  let raw_kind: Str = raw.get("kind")?
  let kind = types.parse_source_kind(raw_kind)?
  let architectures: List[Str] = raw.get("architectures")?
  let raw_checksums: List[Record] = raw.get("checksums")?

  if architectures.len() == 0 {
    return Err(types.PmError.PackageContract(f"${name}: upstream source ${source.display()} has no target architectures"))
  }

  var applies_to_aarch64 = false
  var architecture_seen: Map[Bool] = {}

  for architecture in architectures {
    if architecture_seen.has(architecture) {
      return Err(types.PmError.PackageContract(f"${name}: upstream source ${source.display()} repeats architecture ${architecture}"))
    }

    if architecture != "aarch64" and architecture != "all" {
      return Err(
        types.PmError.PackageContract(
          f"${name}: upstream source ${source.display()} must apply to aarch64 or all, not ${architecture}",
        ),
      )
    }

    if architecture == "aarch64" or architecture == "all" {
      applies_to_aarch64 = true
    }

    architecture_seen[architecture] = true
  }

  if ! applies_to_aarch64 {
    return Err(types.PmError.PackageContract(f"${name}: upstream source ${source.display()} does not apply to aarch64"))
  }

  var checksums: List[types.SourceChecksum] = []
  var applicable_checksums = 0
  var checksum_seen: Map[Bool] = {}

  for raw_checksum in raw_checksums {
    let checksum = decode_source_checksum(name, raw_checksum)?

    if checksum_seen.has(checksum.arch) {
      return Err(types.PmError.PackageContract(f"${name}: upstream source ${source.display()} repeats ${checksum.arch} checksum"))
    }

    if checksum.arch == "aarch64" or checksum.arch == "all" {
      applicable_checksums += 1
    }

    if checksum.sha256 == "SKIP" and ! source_is_repository_local(source) {
      return Err(types.PmError.PackageContract(f"${name}: remote source ${source.display()} may not use SKIP"))
    }

    checksum_seen[checksum.arch] = true
    checksums = checksums.push(checksum)
  }

  if applicable_checksums != 1 {
    return Err(
      types.PmError.PackageContract(
        f"${name}: upstream source ${source.display()} needs exactly one aarch64 or all checksum",
      ),
    )
  }

  {source, kind, architectures, checksums}
}

proc decode_filetree_entry(name: Str, raw: Record) [error] -> Result[types.FileTreeEntry] {
  let path_value: Path = raw.get("path")?
  let raw_kind: Str = raw.get("kind")?
  let kind = types.parse_file_kind(raw_kind)?
  let normalized = path_value.normalize()
  let raw_path = path_value.display()

  if raw_path == "" or normalized.display() == "" or normalized.display() == "." {
    return Err(types.PmError.PackageContract(f"${name}: filetree path must be nonempty"))
  }

  if raw_path != normalized.display() or raw_path.starts_with("/") or raw_path == ".." or raw_path.starts_with("../") or "/../" in raw_path {
    return Err(types.PmError.PackageContract(f"${name}: filetree path ${raw_path} must be normalized and relative"))
  }

  {path: normalized, kind}
}

proc decode_upstream_sources(name: Str, raw_sources: List[Record]) [error] -> Result[List[types.UpstreamSource]] {
  var sources: List[types.UpstreamSource] = []

  for raw_source in raw_sources {
    sources = sources.push(decode_upstream_source(name, raw_source)?)
  }

  sources
}

proc decode_filetree(name: Str, raw_entries: List[Record]) [error] -> Result[List[types.FileTreeEntry]] {
  var entries: List[types.FileTreeEntry] = []
  var seen: Map[Bool] = {}

  for raw_entry in raw_entries {
    let entry = decode_filetree_entry(name, raw_entry)?
    let path_text = entry.path.display()

    if seen.has(path_text) {
      return Err(types.PmError.PackageContract(f"${name}: filetree repeats ${path_text}"))
    }

    seen[path_text] = true
    entries = entries.push(entry)
  }

  entries
}

proc select_filetree(metadata: PackageMetadata) [env, error] -> Result[List[Record]] {
  let arch = util.machine_arch()?

  if arch == "aarch64" and metadata.has_filetree_aarch64 {
    return metadata.filetree_aarch64
  }

  if arch == "x86_64" and metadata.has_filetree_x86_64 {
    return metadata.filetree_x86_64
  }

  metadata.filetree
}

proc is_production_recipe_directory(dir: Path) [] -> Bool {
  dir.parent.name == "repo"
}

proc decode_metadata(pkgbuild: Path) [fs, error] -> Result[PackageMetadata] {
  let dynamic = module.load(pkgbuild)?
  let name: Str = dynamic.get("name").context("package-load", pkgbuild.display())?
  let ver: Str = dynamic.get("ver").context("package-load", pkgbuild.display())?
  let rel: Str = dynamic.get("rel").context("package-load", pkgbuild.display())?
  let deps: List[Str] = dynamic.get("deps").context("package-load", pkgbuild.display())?
  let mkdeps_host: List[Str] = dynamic.get("mkdeps_host").context("package-load", pkgbuild.display())?
  let upstream_sources: List[Record] = dynamic.get("upstream_sources").context("package-load", pkgbuild.display())?
  let filetree: List[Record] = dynamic.get("filetree").context("package-load", pkgbuild.display())?
  let has_build = dynamic.has("build")
  var mkdeps_target: List[Str] = []
  let has_filetree_aarch64 = dynamic.has("filetree_aarch64")
  let has_filetree_x86_64 = dynamic.has("filetree_x86_64")
  var filetree_aarch64: List[Record] = []
  var filetree_x86_64: List[Record] = []

  if dynamic.has("mkdeps_target") {
    mkdeps_target = dynamic.get("mkdeps_target")?
  }

  if has_filetree_aarch64 {
    filetree_aarch64 = dynamic.get("filetree_aarch64")?
  }

  if has_filetree_x86_64 {
    filetree_x86_64 = dynamic.get("filetree_x86_64")?
  }

  let has_package_kind = dynamic.has("package_kind")
  var package_kind = ""
  var nostrip = false
  var source_mirror = true

  if has_package_kind {
    package_kind = dynamic.get("package_kind")?
  }

  if dynamic.has("nostrip") {
    nostrip = dynamic.get("nostrip")?
  }

  if dynamic.has("source_mirror") {
    source_mirror = dynamic.get("source_mirror")?
  }

  {
    name,
    ver,
    rel,
    deps,
    mkdeps_host,
    mkdeps_target,
    upstream_sources,
    filetree,
    filetree_aarch64,
    has_filetree_aarch64,
    filetree_x86_64,
    has_filetree_x86_64,
    has_build,
    package_kind,
    has_package_kind,
    nostrip,
    source_mirror,
  }
}

## Loads, decodes, and validates one package recipe into its typed metadata record.
export proc load_package(dir: Path) [fs, env, error] -> Result[types.Package] {
  let pkgbuild = fp"${dir}/PKGBUILD.xsh"

  if ! fs.exists(pkgbuild)? {
    return Err(types.PmError.PackageContract(f"${dir.display()} does not contain PKGBUILD.xsh"))
  }

  let metadata = decode_metadata(pkgbuild).context("package-load", pkgbuild.display())?
  let name = metadata.name
  let ver = metadata.ver
  let rel = metadata.rel
  let mkdeps_target = metadata.mkdeps_target
  let nostrip = metadata.nostrip
  let source_mirror = metadata.source_mirror

  validate_package_name(name)?

  if ver == "" {
    return Err(types.PmError.PackageContract(f"${name}: ver must be nonempty"))
  }

  validate_positive_release(name, rel)?
  validate_dependencies(name, "deps", metadata.deps)?
  validate_dependencies(name, "mkdeps_host", metadata.mkdeps_host)?
  validate_dependencies(name, "mkdeps_target", mkdeps_target)?

  if is_production_recipe_directory(dir) and dir.name != name {
    return Err(types.PmError.PackageContract(f"${name}: production recipe directory ${dir.name} does not match package name"))
  }

  if is_production_recipe_directory(dir) and ! metadata.has_package_kind {
    return Err(types.PmError.PackageContract(f"${name}: production recipe must export package_kind"))
  }

  let kind = if metadata.has_package_kind { types.parse_package_kind(metadata.package_kind)? } else { types.Payload }
  let upstream_sources = decode_upstream_sources(name, metadata.upstream_sources)?
  let filetree = decode_filetree(name, select_filetree(metadata)?)?

  if kind == types.Payload {
    if ! metadata.has_build {
      return Err(types.PmError.PackageContract(f"${name}: payload package must export build"))
    }

    if ! fs.exists(fp"${dir}/proof.xsh")? {
      return Err(types.PmError.PackageContract(f"${name}: payload package must contain proof.xsh"))
    }
  } else if filetree.len() > 0 {
    return Err(types.PmError.PackageContract(f"${name}: metapackage may not declare payload filetree entries"))
  }

  {
    dir,
    name,
    ver,
    rel,
    kind,
    deps: metadata.deps,
    mkdeps_host: metadata.mkdeps_host,
    mkdeps_target,
    upstream_sources,
    filetree,
    nostrip,
    source_mirror,
  }
}

proc load_dynamic_recipe(pkg: types.Package) [fs, error] -> Result[Any] {
  let pkgbuild = fp"${pkg.dir}/PKGBUILD.xsh"

  if ! fs.exists(pkgbuild)? {
    return Err(types.PmError.PackageContract(f"${pkg.name}: dynamic recipe is unavailable at ${pkgbuild.display()}"))
  }

  module.load(pkgbuild)?
}

## Invokes the optional dynamic `prepare` procedure for a loaded package.
export proc call_prepare(pkg: types.Package, src: Path) [fs, process, env, error] {
  let dynamic = load_dynamic_recipe(pkg)?

  if dynamic.has("prepare") {
    let prepare: Proc = dynamic.get("prepare")?
    prepare.call(src)?
  }
}

## Invokes the required payload `build` procedure through the dynamic recipe boundary.
export proc call_build(pkg: types.Package, src: Path, dest: Path) [fs, process, env, error] {
  if pkg.kind == types.Meta {
    return
  }

  let dynamic = load_dynamic_recipe(pkg)?

  if ! dynamic.has("build") {
    return Err(types.PmError.PackageContract(f"${pkg.name}: payload package lost its build procedure"))
  }

  let build: Proc = dynamic.get("build")?

  cd src {
    build.call(dest)?
  } ?
}

## Invokes the optional dynamic `prepare_sources` procedure for a loaded package.
export proc call_prepare_sources(pkg: types.Package, src: Path) [fs, process, env, error] {
  let dynamic = load_dynamic_recipe(pkg)?

  if dynamic.has("prepare_sources") {
    let prepare_sources: Proc = dynamic.get("prepare_sources")?
    prepare_sources.call(src)?
  }
}
