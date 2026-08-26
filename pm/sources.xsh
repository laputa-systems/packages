##! PM sources operations and shared package-manager policy.
use fingerprint
use recipe
use types
use util

# `repository/` names a declared package-repository input rather than a path
# relative to an isolated recipe copy. The executor supplies its exact
# repository root, so recipes can stage repository-owned source trees without
# `..` traversal or an ambient working directory.
pure sources_is_repository_input(source: Str) -> Bool {
  source.starts_with("repository/")
}

proc sources_repository_input_path(source: Str) [fs, env, error] -> Result[Path] {
  let root = (env.get("XSH_PM_REPOSITORY_ROOT") ?? "").trim()
  let relative = fp"${source.replace("repository/", "")}".normalize()

  if root == "" {
    return Err(types.PmError.PackageContract(f"repository source ${source} needs XSH_PM_REPOSITORY_ROOT"))
  }

  let _ = util.ensure_relative_path(relative, f"repository source ${source}")?
  fp"${root}/${relative}"
}

## Exported PM declaration `ensure_source_dest`.
export pure ensure_source_dest(dest: Path) -> Result[Unit] {
  let _ = util.ensure_relative_path(dest, "source destination")?
}

## Exported PM declaration `source_checksum`.
export proc source_checksum(source: types.UpstreamSource, arch: Str) [error] -> Result[Str] {
  for checksum in source.checksums {
    if checksum.arch == arch or checksum.arch == "all" {
      return checksum.sha256
    }
  }

  Err(types.PmError.SourceChecksum(f"no checksum for ${source.source.display()} on ${arch}"))
}

proc sources_response_header(headers: List[Record], name: Str) [] -> Str {
  for header in headers {
    if header.name == name or name == "location" and header.name == "Location" {
      return header.value
    }
  }

  ""
}

proc sources_resolve_download_redirect(url: Str) [net] -> Str {
  let response = net.request({
    method: "GET",
    url: url,
    redirects: 0,
    max_body_bytes: 4096,
    pool: "pm",
    fail_status: false,
  })

  match response {
    Ok(result) => {
      if result.status >= 300 and result.status < 400 {
        let location = sources_response_header(result.headers, "location")

        if location.starts_with("http://") or location.starts_with("https://") {
          return location
        }
      }
    }
    Err(_) => {}
  }

  url
}

## Exported PM declaration `try_download_url_to_cache`.
export proc try_download_url_to_cache(url: Str, dest: Path) [fs, net, error] -> Result[Bool] {
  if fs.exists(dest)? {
    return true
  }

  if dest.name == "" {
    return false
  }

  fs.mkdir(dest.parent)?
  let tmp = fp"${dest.parent}/.${dest.name}.tmp"
  fs.remove(tmp, missing_ok: true)?
  defer fs.remove(tmp, missing_ok: true)?

  if url.starts_with("file://") {
    let source = fp"${url.replace("file://", "")}"

    if fs.exists(source)? {
      fs.copy(source, tmp, overwrite: true)?
      fs.rename(tmp, dest, overwrite: true)?
      return true
    }

    return false
  }

  let download_url = sources_resolve_download_redirect(url)

  let response = net.download({
    url: download_url,
    dest: tmp,
    atomic: true,
    overwrite: true,
    pool: "pm",
    connect_timeout: 10s,
    timeout: 1800s,
    fail_status: true,
  })

  match response {
    Ok(_) => {
      fs.rename(tmp, dest, overwrite: true)?
      return true
    }
    Err(_) => fs.remove(tmp, missing_ok: true)?
  }

  false
}

## Exported PM declaration `download_url_to_cache`.
export proc download_url_to_cache(url: Str, dest: Path) [fs, net, time, error] {
  if dest.name == "" {
    return Err(types.PmError.SourceName(f"URL has no file name: ${url}"))
  }

  if url.starts_with("file://") {
    if try_download_url_to_cache(url, dest)? {
      return
    }

    return Err(types.PmError.DownloadFailed(f"failed to download ${url}"))
  }

  retry [1s, 2s, 4s, 15s, 60s] {
    let downloaded = try_download_url_to_cache(url, dest)?

    match downloaded {
      true => Ok()
      false => Err(types.PmError.DownloadFailed(f"failed to download ${url}"))
    }
  }?
}

## Exported PM declaration `checkout_git_source`.
export proc checkout_git_source(source: Str, dest: Path) [fs, process, env, error] {
  if fs.exists(dest)? {
    return
  }

  var git = p"git"

  match process.which("git") {
    Ok(tool) => git = tool
    Err(_) => return Err(types.PmError.DownloadTool("git is required for git sources"))
  }

  fs.remove(dest, missing_ok: true)?
  fs.mkdir(dest.parent)?
  let url = util.git_source_url(source)
  let clone = run.status $git clone --depth 1 $url $dest ?

  if ! clone.ok {
    fs.remove(dest, missing_ok: true)?
    return Err(types.PmError.DownloadFailed(f"failed to clone ${url}"))
  }

  let rev = util.git_source_ref(source)

  if rev != "" {
    var checkout_ok = true

    cd dest {
      let checkout = run.status $git checkout $rev ?
      checkout_ok = checkout.ok
    } ?

    if ! checkout_ok {
      fs.remove(dest, missing_ok: true)?
      return Err(types.PmError.DownloadFailed(f"failed to checkout ${rev} from ${url}"))
    }
  }
}

## Exported PM declaration `resolve_source`.
export proc resolve_source(
  work: Path,
  pkg: types.Package,
  line: types.SourceLine,
  arch: Str,
  force_download: Bool,
) [fs, net, process, env, time, error] -> Result[types.ResolvedSource] {
  ensure_source_dest(line.dest)?
  let source = util.source_vars(line.source, pkg, arch)?

  if source == "" {
    return Err(types.PmError.SourceName(f"${pkg.name} has an empty source"))
  }

  if util.is_git_source(source) {
    let cache = util.source_cache_path(work, pkg, line, source)?

    if force_download {
      fs.remove(cache, missing_ok: true)?
    }

    checkout_git_source(source, cache)?
    return {path: cache, kind: "git"}
  }

  if util.is_url_source(source) {
    let cache = util.source_cache_path(work, pkg, line, source)?

    if force_download {
      fs.remove(cache, missing_ok: true)?
    }

    download_url_to_cache(source, cache)?
    return {path: cache, kind: "file"}
  }

  let source_path = fp"${source}"
  var local = source_path

  if sources_is_repository_input(source) {
    local = sources_repository_input_path(source)?
  } else if ! source.starts_with("/") {
    # Recipe-local paths are durable package inputs, including explicit parent
    # inputs such as laputa-pm's checked-in PM entrypoint.  Normalize after
    # anchoring to the typed recipe directory so no process cwd participates.
    local = fp"${pkg.dir}/${source_path}".normalize()
  }

  if ! fs.exists(local)? {
    return Err(types.PmError.SourceNotFound(f"${pkg.name} source not found: ${source}"))
  }

  let metadata = fs.metadata(local)?
  {path: local, kind: metadata.kind}
}

## Exported PM declaration `verify_source_checksum`.
export proc verify_source_checksum(source_path: Path, checksum: Str, kind: Str) [fs, error] {
  if checksum == "SKIP" {
    return
  }

  if kind == "dir" or kind == "git" {
    return Err(types.PmError.SourceChecksum(f"${source_path.display()} must use SKIP because it is not a regular file"))
  }

  hash.verify_file(source_path, sha256: checksum)?
}

pure first_archive_path_component(path_value: Path) -> Str {
  for part in path_value.display().split("/") {
    if part != "" and part != "." {
      return part
    }
  }

  ""
}

## Exported PM declaration `tar_source_strip_components`.
export proc tar_source_strip_components(source_path: Path) [fs, error] -> Result[Int] {
  let entries = archive.tar_list(source_path)?
  var first = ""
  var saw_entry = false

  for entry in entries {
    let component = first_archive_path_component(entry.path)

    if component != "" and component != "pax_global_header" {
      if ! saw_entry {
        first = component
        saw_entry = true
      } else if component != first {
        return 0
      }
    }
  }

  if saw_entry {
    return 1
  }

  0
}

## Exported PM declaration `stage_resolved_source`.
export proc stage_resolved_source(
  _: types.Package,
  line: types.SourceLine,
  source_path: Path,
  resolved_kind: Str,
  source_kind: types.SourceKind,
  checksum: Str,
  src: Path,
) [fs, error] {
  verify_source_checksum(source_path, checksum, resolved_kind)?
  let dest = util.source_stage_dir(src, line)

  if source_kind == types.source_git() or resolved_kind == "git" {
    fs.mkdir(dest)?
    prune_git_dirs(source_path)?
    fs.copy_tree(source_path, dest, parents: true, overwrite: true)?
    return
  }

  if source_kind == types.source_directory() or resolved_kind == "dir" {
    fs.mkdir(dest)?
    fs.copy_tree(source_path, dest, parents: true, overwrite: true)?
    return
  }

  if source_kind == types.source_archive() and util.is_tar_source(source_path) or source_kind == types.source_auto() and util.is_tar_source(
    source_path,
  ) {
    fs.remove(dest, missing_ok: true)?
    dest.parent.mkdir()?
    archive.tar_extract(source_path, dest, tar_source_strip_components(source_path)?, "auto", true)?
    return
  }

  if source_kind == types.source_zip() or source_kind == types.source_auto() and util.is_zip_source(source_path) {
    fs.remove(dest, missing_ok: true)?
    dest.parent.mkdir()?
    archive.zip_extract(source_path, dest, overwrite: true)?
    return
  }

  if source_kind == types.source_cpio() or source_kind == types.source_auto() and util.is_cpio_source(source_path) {
    fs.remove(dest, missing_ok: true)?
    dest.parent.mkdir()?
    archive.cpio_extract(source_path, dest, overwrite: true)?
    return
  }

  fs.mkdir(dest)?
  fs.install(source_path, fp"${dest}/${source_path.name}", 0o644, parents: true, overwrite: true)?
}

## Exported PM declaration `stage_package_sources`.
export proc stage_package_sources(
  work: Path,
  pkg: types.Package,
  src: Path,
  force_download: Bool,
) [fs, net, process, env, time, error] {
  let arch = util.machine_arch()?
  var entries = []

  for source in pkg.upstream_sources {
    if source.architectures.len() == 0 or "all" in source.architectures or arch in source.architectures {
      let line = util.parse_source_line(source.source)?
      entries = entries.push({source, line})
    }
  }

  if entries.len() == 0 {
    return
  }

  var resolved_sources = []

  for entry in entries {
    let resolved = resolve_source(work, pkg, entry.line, arch, force_download)?

    resolved_sources = resolved_sources.push(
      {source: entry.source, line: entry.line, path: resolved.path, kind: resolved.kind},
    )
  }

  for resolved in resolved_sources {
    let checksum = source_checksum(resolved.source, arch)?

    stage_resolved_source(
      pkg,
      resolved.line,
      resolved.path,
      resolved.kind,
      resolved.source.kind,
      checksum,
      src,
    )?
  }
}

## Exported PM declaration `prune_git_dirs`.
export proc prune_git_dirs(src: Path) [fs, error] {
  let git_dirs = fs.walk(src, gitignore: false) |> where .kind == "dir" and .name == ".git"

  for entry in git_dirs {
    fs.remove(entry.path, missing_ok: true)?
  }
}

proc expected_source_sha256(out: Path, pkg: types.Package, arch: Str) [fs, error] -> Result[Str] {
  let index = util.remote_index_cache_path(out)

  if ! fs.exists(index)? {
    return ""
  }

  let rows: List[Record] = json.read(index)?

  for row in rows {
    if row.get("arch")? == arch and row.get("name")? == pkg.name and row.get("ver")? == pkg.ver and row.get("rel")? == pkg.rel {
      return row.get("source_sha256")?
    }
  }

  ""
}

proc validate_source_mirror(out: Path, pkg: types.Package, mirror: Path) [fs, env, error] -> Result[Bool] {
  let expected = expected_source_sha256(out, pkg, util.machine_arch()?)?

  if expected == "" {
    return true
  }

  let actual = hash.sha256(mirror)?.hex()

  if actual == expected {
    return true
  }

  fs.remove(mirror, missing_ok: true)?
  false
}

pure source_mirror_fingerprint_target(arch: Str) -> types.Target {
  if arch == "aarch64" {
    return types.target_aarch64()
  }

  types.target_reserved()
}

proc source_mirror_build_input(pkg: types.Package) [fs, env, error] -> Result[Str] {
  fingerprint.package_build_input(pkg.dir.parent.parent, pkg, source_mirror_fingerprint_target(util.target_arch()?))?
}

## Exported PM declaration `prepare_source_tree`.
export proc prepare_source_tree(pkg: types.Package, src: Path) [fs, process, env, error] {
  recipe.call_prepare_sources(pkg, src)?
}

## Exported PM declaration `try_fetch_source_mirror_from_repo`.
export proc try_fetch_source_mirror_from_repo(out: Path, pkg: types.Package) [fs, net, env, error] {
  let arch = util.machine_arch()?
  let mirror = util.source_mirror_path_for_arch(out, pkg, arch)

  if fs.exists(mirror)? {
    return
  }

  fs.mkdir(mirror.parent)?
  let rel = util.remote_source_rel_for_arch(arch, pkg.name, pkg.ver, pkg.rel)

  let urls = [
    (env.get("XSH_PM_PUBLIC_REPO") ?? env.get("R2_PUBLIC_URL") ?? "").trim(),
    (env.get("XSH_PM_REPO") ?? env.get("LAPUTA_REPO") ?? "").trim(),
  ]

  var seen: Map[Bool] = {}

  for repo in urls {
    if repo != "" and ! seen.get(repo, false) {
      seen[repo] = true

      if util.is_file_url(repo) {
        let source = util.repo_file_path(repo, rel)?

        if fs.exists(source)? {
          fs.copy(source, mirror, overwrite: true)?
          let _ = validate_source_mirror(out, pkg, mirror)?
          return
        }
      } else if try_download_url_to_cache(util.repo_url_for(repo, rel)?, mirror)? {
        let _ = validate_source_mirror(out, pkg, mirror)?
        return
      }
    }
  }
}

## Exported PM declaration `use_source_mirror`.
export proc use_source_mirror(out: Path, pkg: types.Package, src: Path) [fs, env, error] -> Result[Bool] {
  let arch = util.machine_arch()?
  let mirror = util.source_mirror_path_for_arch(out, pkg, arch)

  if ! fs.exists(mirror)? {
    return false
  }

  if ! validate_source_mirror(out, pkg, mirror)? {
    return false
  }

  fs.remove(src, missing_ok: true)?
  fs.mkdir(src)?

  match archive.tar_extract(mirror, src) {
    Ok(_) => return true
    Err(_) => {
      fs.remove(src, missing_ok: true)?
      fs.mkdir(src)?
      return false
    }
  }
}

## Exported PM declaration `pack_source_mirror`.
export proc pack_source_mirror(out: Path, pkg: types.Package, src: Path) [fs, env, error] {
  if pkg.upstream_sources.len() == 0 or ! pkg.source_mirror {
    return
  }

  prune_git_dirs(src)?
  let arch = util.machine_arch()?
  let mirror = util.source_mirror_path_for_arch(out, pkg, arch)
  let manifest = util.source_manifest_path_for_arch(out, pkg, arch)
  fs.mkdir(mirror.parent)?
  archive.tar_create(mirror, src, [p"."], compression: "bz2", overwrite: true)?
  var entries = []

  for entry in fs.walk(src) |> sort-by .path {
    let rel = entry.path.strip_prefix(src)?
    let metadata = fs.metadata(entry.path)?
    var sha256 = ""
    var target = ""

    if metadata.kind == "file" {
      sha256 = hash.sha256(entry.path)?.hex()
    } else if metadata.kind == "symlink" {
      target = entry.path.readlink()?.display()
    }

    entries = entries.push({
      path: rel.display(),
      kind: metadata.kind,
      mode: metadata.mode % 4096,
      size: metadata.size,
      sha256,
      target,
    })
  }

  json.write(
    manifest,
    {
      format: "laputa-source-manifest-1",
      name: pkg.name,
      ver: pkg.ver,
      rel: pkg.rel,
      arch,
      build_input: source_mirror_build_input(pkg)?,
      archive_sha256: hash.sha256(mirror)?.hex(),
      entries,
    },
  )?
}

## Exported PM declaration `prepare_package_source_tree`.
export proc prepare_package_source_tree(
  work: Path,
  out: Path,
  pkg: types.Package,
  src: Path,
  force_download: Bool,
  allow_mirror: Bool,
  pack_mirror: Bool,
) [fs, net, process, env, time, error] {
  if allow_mirror and pkg.source_mirror and ! force_download {
    let mirror_fetch_started = time.now()
    print --flush "pm-build-source-start" $pkg.name "mirror-fetch"
    try_fetch_source_mirror_from_repo(out, pkg)?
    print --flush "pm-build-source-done" $pkg.name "mirror-fetch" ${time.now() - mirror_fetch_started} "ms"
  }

  var used_mirror = false

  if allow_mirror and pkg.source_mirror and ! force_download {
    let mirror_stage_started = time.now()
    print --flush "pm-build-source-start" $pkg.name "mirror-stage"
    used_mirror = use_source_mirror(out, pkg, src)?
    print --flush "pm-build-source-done" $pkg.name "mirror-stage" ${time.now() - mirror_stage_started} "ms"
  }

  if ! used_mirror {
    let stage_started = time.now()
    print --flush "pm-build-source-start" $pkg.name "fetch-stage"
    stage_package_sources(work, pkg, src, force_download)?
    print --flush "pm-build-source-done" $pkg.name "fetch-stage" ${time.now() - stage_started} "ms"
  }

  let tree_started = time.now()
  print --flush "pm-build-source-start" $pkg.name "prepare-tree"
  prepare_source_tree(pkg, src)?
  prune_git_dirs(src)?
  print --flush "pm-build-source-done" $pkg.name "prepare-tree" ${time.now() - tree_started} "ms"

  if pack_mirror {
    pack_source_mirror(out, pkg, src)?
  }
}

## Exported PM declaration `generate_checksums_for`.
export proc generate_checksums_for(
  work: Path,
  pkg: types.Package,
  arch: Str,
) [fs, net, process, env, time, error] -> Result[List[Str]] {
  var generated = []

  for source in pkg.upstream_sources {
    continue when source.architectures.len() > 0 and "all" not in source.architectures and arch not in source.architectures
    let line = util.parse_source_line(source.source)?
    let resolved = resolve_source(work, pkg, line, arch, true)?
    let stored = source_checksum(source, arch)?

    if stored == "SKIP" or resolved.kind == "dir" or resolved.kind == "git" {
      generated = generated.push("SKIP")
    } else {
      let digest = hash.sha256(resolved.path)?.hex()
      generated = generated.push(digest)
    }
  }

  generated
}

## Exported PM declaration `collect_checksum_updates`.
export proc collect_checksum_updates(
  work: Path,
  pkg: types.Package,
) [fs, net, process, env, time, error] -> Result[List[types.ChecksumUpdate]] {
  let arch = util.machine_arch()?
  let generated = generate_checksums_for(work, pkg, arch)?
  [{field: f"upstream_sources:${arch}", values: generated}]
}

## Exported PM declaration `write_checksum_field`.
export proc write_checksum_field(pkg: types.Package, field: Str, values: List[Str]) [fs, error] {
  let field_parts = field.split(":")

  if field_parts.len() != 2 or field_parts[0] != "upstream_sources" {
    return Err(types.PmError.ChecksumField(f"unsupported checksum field ${field}"))
  }

  let arch = field_parts[1]
  let pkgbuild = fp"${pkg.dir}/PKGBUILD.xsh"
  let body = fs.read_text(pkgbuild)?
  let lines = body.split("\n")
  let has_arch_specific = f"arch: \"${arch}\"" in body
  var output = []
  var in_sources = false
  var found = false
  var value_index = 0

  for line in lines {
    let trimmed = line.trim()

    if ! in_sources and trimmed.starts_with("export let upstream_sources = [") {
      in_sources = true
      output = output.push(line)
      continue
    }

    if in_sources {
      if trimmed == "]" {
        in_sources = false
      } else if (f"arch: \"${arch}\"" in line or ! has_arch_specific and "arch: \"all\"" in line) and "sha256: \"" in line {
        if value_index >= values.len() {
          return Err(
            types.PmError.ChecksumField(f"${pkgbuild.display()} has fewer ${arch} checksum entries than expected"),
          )
        }

        let marker = "sha256: \""
        let parts = line.split(marker)
        let old = parts.get(1, "").split("\"").get(0, "")
        let value = values.get(value_index)?
        output = output.push(line.replace(f"${old}\"", f"${value}\""))
        value_index += 1
        found = true
        continue
      }
    }

    output = output.push(line)
  }

  if ! found or value_index != values.len() {
    return Err(types.PmError.ChecksumField(f"${pkgbuild.display()} has no complete ${arch} checksum field"))
  }

  fs.write_atomic(pkgbuild, output.join("\n"))?
}

## Exported PM declaration `audit_source_mirrors`.
export proc audit_source_mirrors(out: Path, packages: List[types.Package]) [fs, env, error] {
  var missing = []

  for pkg in packages {
    if pkg.upstream_sources.len() == 0 or ! pkg.source_mirror {
      print ${pkg.name} "source-mirror" "disabled"
      continue
    }

    let arch = util.machine_arch()?
    let mirror = util.source_mirror_path_for_arch(out, pkg, arch)
    let manifest = util.source_manifest_path_for_arch(out, pkg, arch)

    if ! fs.exists(mirror)? or ! fs.exists(manifest)? {
      missing = missing.push(pkg.name)
      print ${pkg.name} "source-mirror" "missing"
      continue
    }

    let actual = hash.sha256(mirror)?.hex()
    let metadata: Record = json.read(manifest)?
    let recorded: Str = metadata.get("archive_sha256")?

    if actual != recorded {
      return Err(types.PmError.SourceChecksum(f"${pkg.name} source manifest hash mismatch"))
    }

    print ${pkg.name} "source-mirror" "ok"
  }

  if missing.len() > 0 {
    return Err(types.PmError.SourceNotFound(f"${missing.len()} source mirror(s) missing"))
  }
}
