use types
use util

export proc select_checksums(exports: Any, fallback: List[Str]) [env, error] -> Result[List[Str]] {
  let arch = machine_arch()?

  if arch == "x86_64" and exports.has("checksums_x86_64") {
    let checksums: List[Str] = exports.get("checksums_x86_64")?
    return checksums
  }

  if arch == "aarch64" and exports.has("checksums_aarch64") {
    let checksums: List[Str] = exports.get("checksums_aarch64")?
    return checksums
  }

  fallback
}

export pure ensure_source_dest(dest: Path) -> Result[Unit] {
  let _ = ensure_relative_path(dest, "source destination")?
}

export proc response_header(headers: List[Record], name: Str) [] -> Str {
  for header in headers {
    if header.name == name or name == "location" and header.name == "Location" {
      return header.value
    }
  }

  ""
}

export proc resolve_download_redirect(url: Str) [net] -> Str {
  let response = net.request(
    {
      method: "GET",
      url: url,
      redirects: 0,
      max_body_bytes: 4096,
      pool: "pm",
      fail_status: false,
    },
  )

  match response {
    Ok(result) => {
      if result.status >= 300 and result.status < 400 {
        let location = response_header(result.headers, "location")

        if location.starts_with("http://") or location.starts_with("https://") {
          return location
        }
      }
    }
    Err(_) => {}
  }

  url
}

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
    let source = Path.parse(url.replace("file://", ""))?

    if fs.exists(source)? {
      fs.copy(source, tmp, overwrite: true)?
      fs.rename(tmp, dest, overwrite: true)?
      return true
    }

    return false
  }

  let download_url = resolve_download_redirect(url)

  let response = net.download(
    {
      url: download_url,
      dest: tmp,
      atomic: true,
      overwrite: true,
      pool: "pm",
      connect_timeout: 10s,
      timeout: 1800s,
      fail_status: true,
    },
  )

  match response {
    Ok(_) => {
      fs.rename(tmp, dest, overwrite: true)?
      return true
    }
    Err(_) => fs.remove(tmp, missing_ok: true)?
  }

  false
}

export proc download_url_to_cache(url: Str, dest: Path) [fs, net, time, error] {
  if dest.name == "" {
    return Err(PmError.SourceName(f"URL has no file name: ${url}"))
  }

  if url.starts_with("file://") {
    if try_download_url_to_cache(url, dest)? {
      return
    }

    return Err(PmError.DownloadFailed(f"failed to download ${url}"))
  }

  retry [1s, 2s, 4s, 15s, 60s] {
    let downloaded = try_download_url_to_cache(url, dest)?

    match downloaded {
      true => Ok()
      false => Err(PmError.DownloadFailed(f"failed to download ${url}"))
    }
  }?
}

export proc checkout_git_source(source: Str, dest: Path) [fs, process, env, error] {
  if fs.exists(dest)? {
    return
  }

  var git: Path = p"git"

  match process.which("git") {
    Ok(tool) => git = tool
    Err(_) => return Err(PmError.DownloadTool("git is required for git sources"))
  }

  fs.remove(dest, missing_ok: true)?
  fs.mkdir(dest.parent)?
  let url = git_source_url(source)
  let clone = run.status $git clone --depth 1 $url $dest ?

  if ! clone.ok {
    fs.remove(dest, missing_ok: true)?
    return Err(PmError.DownloadFailed(f"failed to clone ${url}"))
  }

  let rev = git_source_ref(source)

  if rev != "" {
    var checkout_ok = true

    cd dest {
      let checkout = run.status $git checkout $rev ?
      checkout_ok = checkout.ok
    } ?

    if ! checkout_ok {
      fs.remove(dest, missing_ok: true)?
      return Err(PmError.DownloadFailed(f"failed to checkout ${rev} from ${url}"))
    }
  }
}

export proc resolve_source(
  work: Path,
  pkg: Package,
  line: SourceLine,
  arch: Str,
  force_download: Bool,
) [fs, net, process, env, time, error] -> Result[ResolvedSource] {
  ensure_source_dest(line.dest)?
  let source = source_vars(line.source, pkg, arch)

  if source == "" {
    return Err(PmError.SourceName(f"${pkg.name} has an empty source"))
  }

  if is_git_source(source) {
    let cache = source_cache_path(work, pkg, line, source)?

    if force_download {
      fs.remove(cache, missing_ok: true)?
    }

    checkout_git_source(source, cache)?
    return {path: cache, kind: "git"}
  }

  if is_url_source(source) {
    let cache = source_cache_path(work, pkg, line, source)?

    if force_download {
      fs.remove(cache, missing_ok: true)?
    }

    download_url_to_cache(source, cache)?
    return {path: cache, kind: "file"}
  }

  let source_path = Path.parse(source)?
  var local = source_path

  if ! source.starts_with("/") {
    local = fp"${pkg.dir}/${source_path}"
  }

  if ! fs.exists(local)? {
    return Err(PmError.SourceNotFound(f"${pkg.name} source not found: ${source}"))
  }

  let metadata = fs.metadata(local)?
  {path: local, kind: metadata.kind}
}

export proc verify_source_checksum(source_path: Path, checksum: Str, kind: Str) [fs, error] {
  if checksum == "SKIP" {
    return
  }

  if kind == "dir" or kind == "git" {
    return Err(PmError.SourceChecksum(f"${source_path.display()} must use SKIP because it is not a regular file"))
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

export proc stage_resolved_source(
  _: Package,
  line: SourceLine,
  source_path: Path,
  kind: Str,
  checksum: Str,
  src: Path,
) [fs, error] {
  verify_source_checksum(source_path, checksum, kind)?
  let dest = source_stage_dir(src, line)

  if kind == "git" {
    fs.mkdir(dest)?
    prune_git_dirs(source_path)?
    fs.copy_tree(source_path, dest, parents: true, overwrite: true)?
    return
  }

  if kind == "dir" {
    fs.mkdir(dest)?
    fs.copy_tree(source_path, dest, parents: true, overwrite: true)?
    return
  }

  if is_tar_source(source_path) {
    fs.remove(dest, missing_ok: true)?
    dest.parent.mkdir()?
    archive.tar_extract(source_path, dest, tar_source_strip_components(source_path)?, "auto", true)?
    return
  }

  if is_zip_source(source_path) {
    fs.remove(dest, missing_ok: true)?
    dest.parent.mkdir()?
    archive.zip_extract(source_path, dest, overwrite: true)?
    return
  }

  if is_cpio_source(source_path) {
    fs.remove(dest, missing_ok: true)?
    dest.parent.mkdir()?
    archive.cpio_extract(source_path, dest, overwrite: true)?
    return
  }

  fs.mkdir(dest)?
  fs.install(source_path, fp"${dest}/${source_path.name}", 0o644, parents: true, overwrite: true)?
}

export proc stage_package_sources(
  work: Path,
  pkg: Package,
  src: Path,
  force_download: Bool,
) [fs, net, process, env, time, error] {
  let arch = machine_arch()?
  var source_index = 0
  var entries: List[Record] = []

  for raw in pkg.sources {
    let line = parse_source_line(raw)?
    entries = entries.push({index: source_index, line})
    source_index += 1
  }

  if entries.len() == 0 {
    return
  }

  let resolved_sources = entries
    |> par-map --jobs=entries.len() { |entry|
      let resolved = resolve_source(work, pkg, entry.line, arch, force_download)?
      {index: entry.index, line: entry.line, path: resolved.path, kind: resolved.kind}
    }

  for resolved in resolved_sources {
    stage_resolved_source(pkg, resolved.line, resolved.path, resolved.kind, pkg.checksums[resolved.index], src)?
  }
}

export proc prune_git_dirs(src: Path) [fs, error] {
  let git_dirs = fs.walk(src, gitignore: false) |> where .kind == "dir" and .name == ".git"

  for entry in git_dirs {
    fs.remove(entry.path, missing_ok: true)?
  }
}

export proc process_source_tree(pkg: Package, src: Path) [fs, process, env, error] {
  let exports = pkg.exports

  if exports.has("process_sources") {
    let process_sources_fn: Proc = exports.get("process_sources")?
    process_sources_fn.call(src)?
  }
}

export proc try_fetch_source_mirror_from_repo(out: Path, pkg: Package) [fs, net, env, error] {
  let arch = machine_arch()?
  let mirror = source_mirror_path_for_arch(out, pkg, arch)

  if fs.exists(mirror)? {
    return
  }

  fs.mkdir(mirror.parent)?
  let rel = remote_source_rel_for_arch(arch, pkg.name, pkg.ver, pkg.rel)

  let urls = [
    (env.get("XSH_PM_PUBLIC_REPO") ?? env.get("R2_PUBLIC_URL") ?? "").trim(),
    (env.get("XSH_PM_REPO") ?? env.get("LAPUTA_REPO") ?? "").trim(),
  ]

  var seen: Map[Bool] = map.empty()

  for repo in urls {
    if repo != "" and ! seen.get(repo, false) {
      seen = seen.set(repo, true)

      if is_file_url(repo) {
        let source = repo_file_path(repo, rel)?

        if fs.exists(source)? {
          fs.copy(source, mirror, overwrite: true)?
          return
        }
      } else if try_download_url_to_cache(repo_url_for(repo, rel)?, mirror)? {
        return
      }
    }
  }
}

export proc use_source_mirror(out: Path, pkg: Package, src: Path) [fs, env, error] -> Result[Bool] {
  let arch = machine_arch()?
  let mirror = source_mirror_path_for_arch(out, pkg, arch)

  if ! fs.exists(mirror)? {
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

  false
}

export proc pack_source_mirror(out: Path, pkg: Package, src: Path) [fs, env, error] {
  if pkg.sources.len() == 0 {
    return
  }

  prune_git_dirs(src)?
  let arch = machine_arch()?
  let mirror = source_mirror_path_for_arch(out, pkg, arch)
  fs.mkdir(mirror.parent)?
  archive.tar_create(mirror, src, [p"."], compression: "gz", overwrite: true)?
}

export proc prepare_package_source_tree(
  work: Path,
  out: Path,
  pkg: Package,
  src: Path,
  force_download: Bool,
  allow_mirror: Bool,
  pack_mirror: Bool,
) [fs, net, process, env, time, error] {
  if allow_mirror and ! force_download {
    try_fetch_source_mirror_from_repo(out, pkg)?

    if use_source_mirror(out, pkg, src)? {
      return
    }
  }

  stage_package_sources(work, pkg, src, force_download)?
  process_source_tree(pkg, src)?
  prune_git_dirs(src)?

  if pack_mirror {
    pack_source_mirror(out, pkg, src)?
  }
}

export proc generate_checksums_for(
  work: Path,
  pkg: Package,
  arch: Str,
  stored: List[Str],
) [fs, net, process, env, time, error] -> Result[List[Str]] {
  var generated: List[Str] = []
  var source_index = 0

  for raw in pkg.sources {
    let line = parse_source_line(raw)?
    let resolved = resolve_source(work, pkg, line, arch, true)?

    if stored[source_index] == "SKIP" or resolved.kind == "dir" or resolved.kind == "git" {
      generated = generated.push("SKIP")
    } else {
      let digest = hash.sha256(resolved.path)?.hex()
      generated = generated.push(digest)
    }

    source_index += 1
  }

  generated
}

export proc collect_checksum_updates(
  work: Path,
  pkg: Package,
) [fs, net, process, env, time, error] -> Result[List[ChecksumUpdate]] {
  var updates: List[ChecksumUpdate] = []
  var added = false
  let exports = pkg.exports

  if exports.has("checksums_aarch64") {
    let stored: List[Str] = exports.get("checksums_aarch64")?
    let generated = generate_checksums_for(work, pkg, "aarch64", stored)?
    updates = updates.push({field: "checksums_aarch64", values: generated})
    added = true
  }

  if exports.has("checksums_x86_64") {
    let stored: List[Str] = exports.get("checksums_x86_64")?
    let generated = generate_checksums_for(work, pkg, "x86_64", stored)?
    updates = updates.push({field: "checksums_x86_64", values: generated})
    added = true
  }

  if ! added {
    let stored = exports.checksums
    let arch = machine_arch()?
    let generated = generate_checksums_for(work, pkg, arch, stored)?
    updates = updates.push({field: "checksums", values: generated})
  }

  updates
}

export proc write_checksum_field(pkg: Package, field: Str, values: List[Str]) [fs, error] {
  let pkgbuild = fp"${pkg.dir}/PKGBUILD.xsh"

  let lines = fs.read_text(pkgbuild)?.split("""
""")

  var output: List[Str] = []
  var in_block = false
  var found = false

  for line in lines {
    let trimmed = line.trim()

    if ! in_block and checksum_field_line(trimmed, field) {
      found = true
      output = output.push(f"export let ${field} = [")

      for value in values {
        output = output.push(f"  \"${value}\",")
      }

      output = output.push("]")

      if ! ("]" in line) {
        in_block = true
      }
    } else if in_block {
      if "]" in line {
        in_block = false
      }
    } else {
      output = output.push(line)
    }
  }

  if ! found {
    return Err(PmError.ChecksumField(f"${pkgbuild.display()} does not contain ${field}"))
  }

  fs.write_atomic(
    pkgbuild,
    output.join("""
"""),
  )?
}
