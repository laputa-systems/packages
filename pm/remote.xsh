use sources
use types
use util

pure default_repo_url() -> Str {
  "https://laputa.17166969.xyz"
}

proc dotenv_lookup(body: Str, name: Str) [] -> Str {
  for raw in body.lines() {
    let stripped = raw.trim()
    continue when stripped == "" or stripped.starts_with("#")
    let line = if stripped.starts_with("export ") { stripped.split("export ").get(1, "").trim() } else { stripped }

    if line.starts_with(f"${name}=") {
      let parts = line.split("=")
      var value_parts: List[Str] = []
      var part_index = 1

      while part_index < parts.len() {
        value_parts = value_parts.push(parts[part_index])
        part_index += 1
      }

      return value_parts.join("=").trim().replace("\"", "").replace("'", "")
    }
  }

  ""
}

proc load_dotenv_value(name: Str) [fs, error] -> Result[Str] {
  if fs.exists(p".env")? {
    let value = dotenv_lookup(fs.read_text(p".env")?, name)

    if value != "" {
      return value
    }
  }

  match fs.gitroot() {
    Ok(root) => {
      let dotenv = fp"${root}/.env"

      if fs.exists(dotenv)? {
        return dotenv_lookup(fs.read_text(dotenv)?, name)
      }
    }
    Err(_) => {}
  }

  ""
}

proc load_env_or_dotenv(names: List[Str]) [fs, env, error] -> Result[Str] {
  for name in names {
    let value = (env.get(name) ?? "").trim()

    if value != "" {
      return value
    }
  }

  for name in names {
    let value = load_dotenv_value(name)?.trim()

    if value != "" {
      return value
    }
  }

  ""
}

export proc load_repo_urls() [fs, env, error] -> Result[RepoUrls] {
  var repo = load_env_or_dotenv(["XSH_PM_REPO", "LAPUTA_REPO"])?
  var public_repo = load_env_or_dotenv(["XSH_PM_PUBLIC_REPO", "R2_PUBLIC_URL"])?

  if repo == "" and (env.get("XSH_PM_OFFLINE") ?? "").trim() != "1" {
    repo = default_repo_url()
  }

  if public_repo == "" and repo == default_repo_url() {
    public_repo = repo
  }

  {repo, public_repo}
}

export proc require_repo_url() [fs, env, error] -> Result[RepoUrls] {
  let repo_urls = load_repo_urls()?

  if repo_urls.repo == "" {
    return Err(PmError.RemoteRepo("set XSH_PM_REPO or LAPUTA_REPO"))
  }

  repo_urls
}

export proc load_auth_token(root: Path) [fs, process, env, error] -> Result[Str] {
  let env_token = load_env_or_dotenv(["LAPUTA_TOKEN"])?

  if env_token != "" {
    return env_token
  }

  let security_output = run.text security find-generic-password -a xsh-pm -s xsh-pm-token -w 2> /dev/null

  match security_output {
    Ok(token) => {
      let trimmed = token.trim()

      if trimmed != "" {
        return trimmed
      }
    }
    Err(_) => {}
  }

  let token_file = auth_token_path(root)

  if fs.exists(token_file)? {
    return fs.read_text(token_file)?.trim()
  }

  ""
}

export proc require_auth_token(root: Path) [fs, process, env, error] -> Result[Str] {
  let token = load_auth_token(root)?

  if token == "" {
    return Err(PmError.Auth("not authenticated; run auth or set LAPUTA_TOKEN"))
  }

  token
}

export proc store_auth_token(root: Path, raw: List[Str]) [fs, process, env, error] {
  var token = ""

  if raw.len() > 0 {
    token = raw[0].trim()
  } else {
    token = load_auth_token(root)?
  }

  if token == "" {
    return Err(PmError.Auth("auth requires a token argument or LAPUTA_TOKEN"))
  }

  let token_file = auth_token_path(root)
  fs.mkdir(token_file.parent)?
  fs.write_atomic(token_file, token)?
  fs.chmod(token_file, 0o600)?
  print "auth" "token" "stored"
}

proc remote_response_header(headers: List[Record], name: Str) [] -> Str {
  for header in headers {
    if header.name == name or name == "location" and header.name == "Location" {
      return header.value
    }
  }

  ""
}

proc remote_resolve_download_redirect(url: Str) [net] -> Str {
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
        let location = remote_response_header(result.headers, "location")

        if location.starts_with("http://") or location.starts_with("https://") {
          return location
        }
      }
    }
    Err(_) => {}
  }

  url
}

export proc try_fetch_repo_file(
  repo: Str,
  rel: Path,
  dest: Path,
  timeout: Duration = 1800s,
) [fs, net, error] -> Result[Str] {
  fs.mkdir(dest.parent)?
  let tmp = fp"${dest.parent}/.${dest.name}.tmp"
  fs.remove(tmp, missing_ok: true)?
  defer fs.remove(tmp, missing_ok: true)?

  if is_file_url(repo) {
    let source = repo_file_path(repo, rel)?

    if fs.exists(source)? {
      fs.copy(source, tmp, overwrite: true)?
      fs.rename(tmp, dest, overwrite: true)?
      return ""
    }

    let missing_url = repo_url_for(repo, rel)?
    return f"${missing_url}: missing file"
  }

  fs.remove(dest, missing_ok: true)?
  let url = repo_url_for(repo, rel)?
  let download_url = remote_resolve_download_redirect(url)

  let response = net.download(
    {
      url: download_url,
      dest: tmp,
      atomic: true,
      overwrite: true,
      pool: "pm",
      connect_timeout: 10s,
      timeout: timeout,
      fail_status: true,
    },
  )

  match response {
    Ok(_) => {
      fs.rename(tmp, dest, overwrite: true)?
      return ""
    }
    Err(err) => {
      fs.remove(tmp, missing_ok: true)?
      return f"${url}: ${err.message}"
    }
  }

  ""
}

export proc fetch_repo_file_with_retry(
  repo: Str,
  rel: Path,
  dest: Path,
  timeout: Duration = 1800s,
) [fs, net, time, error] -> Result[Str] {
  if is_file_url(repo) {
    return try_fetch_repo_file(repo, rel, dest, timeout: timeout)?
  }

  var failure = ""

  match retry [1s, 2s, 4s, 15s, 60s] {
    let attempt_failure = try_fetch_repo_file(repo, rel, dest, timeout: timeout)?

    match attempt_failure {
      "" => Ok("")
      _ => Err(PmError.RemoteFetch(attempt_failure))
    }
  } {
    Ok(_) => failure = ""
    Err(err) => failure = err.message
  }

  failure
}

export proc fetch_repo_file(repo: Str, rel: Path, dest: Path, required: Bool) [fs, net, time, error] {
  let failure = fetch_repo_file_with_retry(repo, rel, dest)?

  if failure == "" {
    return
  }

  if required {
    return Err(PmError.RemoteFetch(failure))
  }
}

export proc net_put_file(url: Str, source: Path, token: Str) [net, error] {
  let response = net.upload(
    {
      method: "PUT",
      url: url,
      source: source,
      headers: [{name: "Authorization", value: f"Bearer ${token}"}],
      pool: "pm",
      fail_status: true,
    },
  )?

  if response.status < 200 or response.status >= 300 {
    return Err(PmError.RemoteUpload(f"failed to upload ${source.name}"))
  }
}

export proc upload_repo_file(repo: Str, rel: Path, source: Path, token: Str, _: Path) [fs, net, error] {
  if is_file_url(repo) {
    let dest = repo_file_path(repo, rel)?
    fs.mkdir(dest.parent)?
    fs.copy(source, dest, overwrite: true)?
    return
  }

  net_put_file(repo_url_for(repo, rel)?, source, token)?
}

export proc upload_large_repo_file(repo: Str, rel: Path, source: Path, token: Str, _: Path) [fs, net, time, error] {
  if is_file_url(repo) {
    let dest = repo_file_path(repo, rel)?
    let partial = fp"${dest.parent}/.${dest.name}.upload"
    fs.mkdir(dest.parent)?
    fs.remove(partial, missing_ok: true)?
    defer fs.remove(partial, missing_ok: true)?
    fs.copy(source, partial, overwrite: true)?
    fs.rename(partial, dest, overwrite: true)?
    return
  }

  let data = source.read_bytes()?
  let chunks = data.chunks(25 * 1024 * 1024)

  if chunks.len() == 0 {
    net_put_file(repo_url_for(repo, rel)?, source, token)?
    return
  }

  let upload_id = f"pm-${time.now()}-${data.sha256().hex()}"
  var chunk_index = 0

  for chunk in chunks {
    let response = net.request(
      {
        method: "PUT",
        url: repo_url_for(repo, fp"_uploads/${upload_id}/${chunk_index}")?,
        body: chunk,
        headers: [{name: "Authorization", value: f"Bearer ${token}"}],
        pool: "pm",
        fail_status: true,
      },
    )?

    if response.status < 200 or response.status >= 300 {
      return Err(PmError.RemoteUpload(f"failed to upload chunk ${chunk_index} for ${source.name}"))
    }

    chunk_index += 1
  }

  let response = net.request(
    {
      method: "POST",
      url: repo_url_for(repo, fp"_uploads/${upload_id}/complete")?,
      body_text: json.encode({rel: rel.display(), chunks: chunks.len()})?,
      headers: [{name: "Authorization", value: f"Bearer ${token}"}, {name: "Content-Type", value: "application/json"}],
      pool: "pm",
      fail_status: true,
    },
  )?

  if response.status < 200 or response.status >= 300 {
    return Err(PmError.RemoteUpload(f"failed to complete chunked upload for ${source.name}"))
  }
}

export proc load_remote_index_from(index_path: Path) [fs, error] -> Result[List[RemotePackage]] {
  if fs.exists(index_path)? {
    let rows: List[Record] = json.read(index_path)?
    return decode_remote_index(rows)
  }

  let empty: List[RemotePackage] = []
  empty
}

proc try_load_remote_index_from_repo(repo: Str, out: Path) [fs, net, error] -> Result[List[RemotePackage]] {
  if is_file_url(repo) {
    return load_remote_index_from(repo_file_path(repo, p"index.json")?)?
  }

  let response = net.request(
    {
      method: "GET",
      url: repo_url_for(repo, p"index.json")?,
      pool: "pm",
      timeout: 15s,
      connect_timeout: 5s,
      max_body_bytes: 10485760,
    },
  )?

  if response.status == 404 {
    let empty: List[RemotePackage] = []
    return empty
  }

  if response.status < 200 or response.status >= 300 {
    return Err(PmError.RemoteIndex(f"failed to fetch remote index: HTTP ${response.status}"))
  }

  let body = response.body.utf8()?
  let rows: List[Record] = json.decode(body)?
  let items = decode_remote_index(rows)?
  fs.mkdir(out)?
  fs.write_atomic(remote_index_cache_path(out), body)?
  items
}

export proc load_remote_index_from_repo(repo: Str, out: Path) [fs, net, time, error] -> Result[List[RemotePackage]] {
  if is_file_url(repo) {
    return try_load_remote_index_from_repo(repo, out)?
  }

  retry [1s, 2s, 4s, 15s, 60s] {
    try_load_remote_index_from_repo(repo, out)?
  }?
}

export proc decode_remote_index(rows: List[Record]) [error] -> Result[List[RemotePackage]] {
  var items = [decode_remote_package(row)? for row in rows]
  items
}

export proc decode_remote_package(row: Record) [error] -> Result[RemotePackage] {
  var arch = "aarch64"
  let empty_target_build_deps: List[Str] = []

  if row.has("arch") {
    let stored_arch: Str = row.get("arch")?
    arch = normalize_arch(stored_arch)
  }

  {
    arch,
    name: row.get("name")?,
    ver: row.get("ver")?,
    rel: row.get("rel")?,
    deps: row.get("deps")?,
    mkdeps: row.get("mkdeps")?,
    target_build_deps: if row.has("target_build_deps") { row.get("target_build_deps")? } else { empty_target_build_deps },
    sha256: row.get("sha256")?,
    size: row.get("size")?,
    tarball: row.get("tarball")?,
    metadata: if row.has("metadata") { row.get("metadata")? } else { "" },
    source_sha256: row.get("source_sha256")?,
    source_tarball: row.get("source_tarball")?,
    metapackage: row.get("metapackage")?,
  }
}

export proc load_cached_remote_index(out: Path) [fs, error] -> Result[List[RemotePackage]] {
  load_remote_index_from(remote_index_cache_path(out))?
}

export proc write_remote_index_cache(out: Path, index: List[RemotePackage]) [fs, error] {
  fs.mkdir(out)?
  json.write(remote_index_cache_path(out), index)?
}

export proc write_remote_index_to_repo(
  repo: Str,
  work: Path,
  out: Path,
  index: List[RemotePackage],
  token: Str,
) [fs, net, error] {
  write_remote_index_cache(out, index)?
  upload_repo_file(repo, p"index.json", remote_index_cache_path(out), token, work)?
}

export proc refresh_remote_index(out: Path) [fs, net, env, time, error] -> Result[List[RemotePackage]] {
  let repo_urls = load_repo_urls()?
  var repo = repo_urls.public_repo

  if repo == "" {
    repo = repo_urls.repo
  }

  if repo == "" {
    if fs.exists(remote_index_cache_path(out))? {
      let index = load_cached_remote_index(out)?
      print "remote-index" index.len() "cached"
      return index
    }

    return Err(PmError.RemoteRepo("set XSH_PM_PUBLIC_REPO, R2_PUBLIC_URL, XSH_PM_REPO, or LAPUTA_REPO"))
  }

  if is_file_url(repo) and ! fs.exists(repo_file_path(repo, p"index.json")?)? {
    let index: List[RemotePackage] = []
    write_remote_index_cache(out, index)?
    print "remote-index" 0 refreshed
    return index
  }

  fetch_repo_file(repo, p"index.json", remote_index_cache_path(out), true)?
  let index = load_cached_remote_index(out)?
  print "remote-index" index.len() "refreshed"
  index
}

export proc ensure_remote_index(out: Path) [fs, net, env, time, error] -> Result[List[RemotePackage]] {
  if fs.exists(remote_index_cache_path(out))? {
    return load_cached_remote_index(out)?
  }

  refresh_remote_index(out)?
}

export proc upsert_remote_package(
  index: List[RemotePackage],
  entry: RemotePackage,
) [error] -> Result[List[RemotePackage]] {
  var updated: List[RemotePackage] = []
  var replaced = false

  for existing in index {
    if existing.arch == entry.arch and existing.name == entry.name {
      updated = updated.push(entry)
      replaced = true
    } else {
      updated = updated.push(existing)
    }
  }

  if ! replaced {
    updated = updated.push(entry)
  }

  let sorted = updated |> sort-by .name
  sorted
}

export proc find_remote_package(index: List[RemotePackage], name: Str) [env, error] -> Result[RemotePackage] {
  let arch = machine_arch()?

  for entry in index {
    if entry.arch == arch and entry.name == name {
      return entry
    }
  }

  return Err(PmError.RemotePackage(f"${name} for ${arch} is not in the remote index"))
}

export proc collect_remote_packages(
  root: Path,
  index: List[RemotePackage],
  names: List[Str],
) [fs, env, error] -> Result[List[RemotePackage]] {
  var packages: List[RemotePackage] = []
  var seen: Map[Bool] = {}
  var pending = names
  var pending_index = 0

  while pending_index < pending.len() {
    let name = pending[pending_index]
    pending_index += 1

    if ! seen.get(name, false) {
      let pkg = find_remote_package(index, name)?
      packages = packages.push(pkg)
      seen[name] = true

      for dep in pkg.deps {
        if ! fs.exists(package_db_path(root, dep))? and ! seen.get(dep, false) {
          pending = pending.push(dep)
        }
      }
    }
  }

  packages
}

export proc order_remote_packages(
  root: Path,
  packages: List[RemotePackage],
) [fs, error] -> Result[List[RemotePackage]] {
  var ordered: List[RemotePackage] = []
  var by_name: Map[Int] = {}
  var pkg_index = 0

  for pkg in packages {
    by_name[pkg.name] = pkg_index
    pkg_index += 1
  }

  var added: Map[Bool] = {}

  while ordered.len() < packages.len() {
    var progressed = false

    for pkg in packages {
      if ! added.get(pkg.name, false) {
        var ready = true

        for dep in pkg.deps {
          if ! by_name.has(dep) {
            if ! fs.exists(package_db_path(root, dep))? {
              return Err(PmError.MissingDependency(f"${pkg.name} depends on missing ${dep}"))
            }
          } else if ! added.get(dep, false) {
            ready = false
          }
        }

        if ready {
          ordered = ordered.push(pkg)
          added[pkg.name] = true
          progressed = true
        }
      }
    }

    if ! progressed {
      return Err(PmError.DependencyCycle("remote package dependency graph did not make progress"))
    }
  }

  ordered
}

export proc verify_cached_tarball(tarball: Path, pkg: RemotePackage) [fs, error] -> Result[Bool] {
  if ! fs.exists(tarball)? {
    return false
  }

  if pkg.sha256 != "" and hash.sha256(tarball)?.hex() != pkg.sha256 {
    fs.remove(tarball, missing_ok: true)?
    return false
  }

  true
}

export proc downloaded_tarball_failure(tarball: Path, pkg: RemotePackage, url: Str) [fs, error] -> Result[Str] {
  if ! fs.exists(tarball)? {
    return f"${url}: download missing after transfer"
  }

  if pkg.sha256 != "" {
    let actual = hash.sha256(tarball)?.hex()

    if actual != pkg.sha256 {
      let metadata = fs.metadata(tarball)?
      fs.remove(tarball, missing_ok: true)?
      return f"${url}: checksum mismatch (expected ${pkg.sha256}, got ${actual}, bytes ${metadata.size})"
    }
  }

  ""
}

export proc download_remote_tarball(out: Path, pkg: RemotePackage) [fs, net, env, time, error] -> Result[Record] {
  let tarball = remote_cache_tarball_path(out, pkg)?

  if verify_cached_tarball(tarball, pkg)? {
    return {tarball, from_cache: true}
  }

  let repo_urls = load_repo_urls()?
  var fetched = false
  var failures: List[Str] = []

  if repo_urls.public_repo != "" {
    let rel = fp"${pkg.tarball}"
    let url = repo_url_for(repo_urls.public_repo, rel)?
    let failure = fetch_repo_file_with_retry(repo_urls.public_repo, rel, tarball)?

    if failure != "" {
      failures = failures.push(failure)
    } else {
      let download_failure = downloaded_tarball_failure(tarball, pkg, url)?

      if download_failure != "" {
        failures = failures.push(download_failure)
      }
    }

    fetched = verify_cached_tarball(tarball, pkg)?
  }

  if ! fetched and repo_urls.repo != "" {
    let rel = fp"${pkg.tarball}"
    let url = repo_url_for(repo_urls.repo, rel)?
    let failure = fetch_repo_file_with_retry(repo_urls.repo, rel, tarball)?

    if failure != "" {
      failures = failures.push(failure)
    } else {
      let download_failure = downloaded_tarball_failure(tarball, pkg, url)?

      if download_failure != "" {
        failures = failures.push(download_failure)
      }
    }

    fetched = verify_cached_tarball(tarball, pkg)?
  }

  if fetched {
    return {tarball, from_cache: false}
  }

  var detail = "no repository URL configured"

  if failures.len() > 0 {
    detail = failures.join("; ")
  }

  return Err(PmError.RemoteFetch(f"failed to fetch ${pkg.name} ${version_id(pkg.ver, pkg.rel)}: ${detail}"))
}

export proc fetch_remote_metadata_sidecar(out: Path, pkg: RemotePackage) [fs, net, env, time, error] -> Result[Record] {
  let metadata = remote_cache_metadata_path(out, pkg)?

  if pkg.metadata == "" {
    return {found: false, path: metadata, from_cache: false}
  }

  if fs.exists(metadata)? {
    return {found: true, path: metadata, from_cache: true}
  }

  let rel = ensure_relative_path(fp"${pkg.metadata}", "remote metadata")?
  let repo_urls = load_repo_urls()?
  var fetched = false
  var failures: List[Str] = []

  if repo_urls.public_repo != "" {
    let failure = fetch_repo_file_with_retry(repo_urls.public_repo, rel, metadata, timeout: 60s)?

    if failure != "" {
      failures = failures.push(failure)
    }

    fetched = fs.exists(metadata)?
  }

  if ! fetched and repo_urls.repo != "" {
    let failure = fetch_repo_file_with_retry(repo_urls.repo, rel, metadata, timeout: 60s)?

    if failure != "" {
      failures = failures.push(failure)
    }

    fetched = fs.exists(metadata)?
  }

  if fetched {
    return {found: true, path: metadata, from_cache: false}
  }

  if failures.len() > 0 {
    return Err(
      PmError.RemoteFetch(
        f"failed to fetch metadata for ${pkg.name} ${version_id(pkg.ver, pkg.rel)}: ${failures.join("; ")}",
      ),
    )
  }

  return {found: false, path: metadata, from_cache: false}
}

export pure package_from_remote(pkg: RemotePackage) -> Result[Package] {
  let pkg_sources: List[Path] = []
  let checksums: List[Str] = []

  {
    dir: p".",
    exports: {},
    name: pkg.name,
    ver: pkg.ver,
    rel: pkg.rel,
    deps: pkg.deps,
    mkdeps: pkg.mkdeps,
    target_build_deps: pkg.target_build_deps,
    sources: pkg_sources,
    checksums,
    nostrip: false,
    extract_install: false,
  }
}

export proc args_are_package_dirs(raw: List[Str]) [fs, error] -> Result[Bool] {
  if raw.len() == 0 {
    return false
  }

  for item in raw {
    if ! fs.exists(fp"${fp"${item}"}/PKGBUILD.xsh")? {
      return false
    }
  }

  true
}

export pure remote_entry_for(
  arch: Str,
  pkg: Package,
  tarball_rel: Str,
  sha256: Str,
  size: Int,
  metadata_rel: Str,
  source_rel: Str,
  source_sha256: Str,
  metapackage: Bool,
) -> RemotePackage {
  return {
    arch,
    name: pkg.name,
    ver: pkg.ver,
    rel: pkg.rel,
    deps: pkg.deps,
    mkdeps: pkg.mkdeps,
    target_build_deps: pkg.target_build_deps,
    sha256,
    size,
    tarball: tarball_rel,
    metadata: metadata_rel,
    source_sha256,
    source_tarball: source_rel,
    metapackage,
  }
}

export proc upload_package_source(
  repo: Str,
  work: Path,
  out: Path,
  pkg: Package,
  token: Str,
) [fs, net, env, time, error] -> Result[UploadedSource] {
  let arch = machine_arch()?
  let mirror = source_mirror_path_for_arch(out, pkg, arch)

  if ! fs.exists(mirror)? {
    return {rel: "", sha256: ""}
  }

  let rel = remote_source_rel_for_arch(arch, pkg.name, pkg.ver, pkg.rel)
  let metadata = fs.metadata(mirror)?

  if metadata.size > 52428800 {
    upload_large_repo_file(repo, rel, mirror, token, work)?
  } else {
    upload_repo_file(repo, rel, mirror, token, work)?
  }

  {rel: rel.display(), sha256: hash.sha256(mirror)?.hex()}
}
