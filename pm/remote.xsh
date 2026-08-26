##! PM remote operations and shared package-manager policy.
use catalog
use sources
use types
use util

## Returns the package names available from one selected remote architecture snapshot.
export pure selected_snapshot_names(index: List[types.RemotePackage], arch: Str) -> List[Str] {
  var names: List[Str] = []

  for pkg in index {
    if pkg.arch == arch and pkg.name not in names {
      names = names.push(pkg.name)
    }
  }

  names |> sort
}

## Attaches one selected remote index snapshot to a typed local catalog.
export proc catalog_with_selected_snapshot(
  value: types.PackageCatalog,
  index: List[types.RemotePackage],
  arch: Str,
) [error] -> Result[types.PackageCatalog] {
  catalog.with_remote_names(value, selected_snapshot_names(index, arch))?
}

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
      var value_parts = []
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

## Exported PM declaration `load_repo_urls`.
export proc load_repo_urls() [fs, env, error] -> Result[types.RepoUrls] {
  var repo = load_env_or_dotenv(["XSH_PM_REPO", "LAPUTA_REPO"])?
  var public_repo = load_env_or_dotenv(["XSH_PM_PUBLIC_REPO", "R2_PUBLIC_URL"])?

  if repo == "" and public_repo == "" and (env.get("XSH_PM_OFFLINE") ?? "").trim() != "1" {
    repo = default_repo_url()
  }

  if public_repo == "" and repo == default_repo_url() {
    public_repo = repo
  }

  {repo, public_repo}
}

## Exported PM declaration `require_repo_url`.
export proc require_repo_url() [fs, env, error] -> Result[types.RepoUrls] {
  let repo_urls = load_repo_urls()?

  if repo_urls.repo == "" {
    return Err(types.PmError.RemoteRepo("set XSH_PM_REPO or LAPUTA_REPO"))
  }

  repo_urls
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

## Exported PM declaration `try_fetch_repo_file`.
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

  if util.is_file_url(repo) {
    let source = util.repo_file_path(repo, rel)?

    if fs.exists(source)? {
      fs.copy(source, tmp, overwrite: true)?
      fs.rename(tmp, dest, overwrite: true)?
      return ""
    }

    let missing_url = util.repo_url_for(repo, rel)?
    return f"${missing_url}: missing file"
  }

  fs.remove(dest, missing_ok: true)?
  let url = util.repo_url_for(repo, rel)?
  let download_url = remote_resolve_download_redirect(url)

  let response = net.download({
    url: download_url,
    dest: tmp,
    atomic: true,
    overwrite: true,
    pool: "pm",
    connect_timeout: 10s,
    timeout: timeout,
    fail_status: true,
  })

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
}

## Exported PM declaration `fetch_repo_file_with_retry`.
export proc fetch_repo_file_with_retry(
  repo: Str,
  rel: Path,
  dest: Path,
  timeout: Duration = 1800s,
) [fs, net, time, error] -> Result[Str] {
  if util.is_file_url(repo) {
    return try_fetch_repo_file(repo, rel, dest, timeout: timeout)?
  }

  var failure = ""

  match retry [1s, 2s, 4s, 15s, 60s] {
    let attempt_failure = try_fetch_repo_file(repo, rel, dest, timeout: timeout)?

    match attempt_failure {
      "" => Ok("")
      _ => Err(types.PmError.RemoteFetch(attempt_failure))
    }
  } {
    Ok(_) => failure = ""
    Err(err) => failure = err.message
  }

  failure
}

## Exported PM declaration `fetch_repo_file`.
export proc fetch_repo_file(repo: Str, rel: Path, dest: Path, required: Bool) [fs, net, time, error] {
  let failure = fetch_repo_file_with_retry(repo, rel, dest)?

  if failure == "" {
    return
  }

  if required {
    return Err(types.PmError.RemoteFetch(failure))
  }
}

## Exported PM declaration `net_put_file`.
export proc net_put_file(url: Str, source: Path, token: Str) [net, error] {
  let response = net.upload({
    method: "PUT",
    url: url,
    source: source,
    headers: [{name: "Authorization", value: f"Bearer ${token}"}],
    pool: "pm",
    fail_status: true,
  })?

  if response.status < 200 or response.status >= 300 {
    return Err(types.PmError.RemoteUpload(f"failed to upload ${source.name}"))
  }
}

## Exported PM declaration `upload_repo_file`.
export proc upload_repo_file(repo: Str, rel: Path, source: Path, token: Str, _: Path) [fs, net, error] {
  if util.is_file_url(repo) {
    let dest = util.repo_file_path(repo, rel)?
    fs.mkdir(dest.parent)?
    fs.copy(source, dest, overwrite: true)?
    return
  }

  net_put_file(util.repo_url_for(repo, rel)?, source, token)?
}

## Publishes one immutable repository object. A file remote receives a temporary copy and rename;
## an existing object is accepted only when its exact bytes already match the requested source.
export proc upload_immutable_repo_file(repo: Str, rel: Path, source: Path, token: Str, work: Path) [fs, net, error] -> Result[Bool] {
  if ! util.is_file_url(repo) {
    let response = net.upload({
      method: "PUT",
      url: util.repo_url_for(repo, rel)?,
      source,
      headers: [
        {name: "Authorization", value: f"Bearer ${token}"},
        {name: "If-None-Match", value: "*"},
      ],
      pool: "pm",
      fail_status: false,
    })?

    if response.status >= 200 and response.status < 300 {
      return true
    }

    if response.status == 409 or response.status == 412 {
      return Err(types.PmError.PackageConflict(f"immutable remote object ${rel.display()} already exists"))
    }

    return Err(types.PmError.RemoteUpload(f"failed to upload immutable remote object ${rel.display()}: HTTP ${response.status}"))
  }

  let dest = util.repo_file_path(repo, rel)?

  if fs.exists(dest)? {
    if hash.sha256(dest)?.hex() == hash.sha256(source)?.hex() {
      return false
    }

    return Err(types.PmError.PackageConflict(f"immutable remote object ${rel.display()} already exists with different bytes"))
  }

  let temporary = fp"${dest.parent}/.${dest.name}.tmp"
  fs.mkdir(dest.parent)?
  fs.remove(temporary, missing_ok: true)?
  defer fs.remove(temporary, missing_ok: true)?
  fs.copy(source, temporary, overwrite: true)?
  fs.rename(temporary, dest)?
  true
}

## Exported PM declaration `upload_large_repo_file`.
export proc upload_large_repo_file(repo: Str, rel: Path, source: Path, token: Str, _: Path) [fs, net, time, error] {
  if util.is_file_url(repo) {
    let dest = util.repo_file_path(repo, rel)?
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
    net_put_file(util.repo_url_for(repo, rel)?, source, token)?
    return
  }

  let upload_id = f"pm-${time.now()}-${data.sha256().hex()}"
  var chunk_index = 0
  var requests = []

  for chunk in chunks {
    requests = requests.push({
      method: "PUT",
      url: util.repo_url_for(repo, fp"_uploads/${upload_id}/${chunk_index}")?,
      body: chunk,
      headers: [{name: "Authorization", value: f"Bearer ${token}"}],
      pool: "pm",
      fail_status: true,
    })

    chunk_index += 1
  }

  # Chunk paths are independent, and request_many keeps result order so errors
  # still identify the source chunk without evaluator worker threads.
  let responses = net.request_many({requests, concurrency: 8, pool: "pm"})?
  chunk_index = 0

  for response in responses {
    match response {
      Ok(_) => {}
      Err(_) => return Err(types.PmError.RemoteUpload(f"failed to upload chunk ${chunk_index} for ${source.name}"))
    }

    chunk_index += 1
  }

  let response = net.request({
    method: "POST",
    url: util.repo_url_for(repo, fp"_uploads/${upload_id}/complete")?,
    body_text: json.encode({rel: rel.display(), chunks: chunks.len()})?,
    headers: [{name: "Authorization", value: f"Bearer ${token}"}, {name: "Content-Type", value: "application/json"}],
    pool: "pm",
    fail_status: true,
  })?

  if response.status < 200 or response.status >= 300 {
    return Err(types.PmError.RemoteUpload(f"failed to complete chunked upload for ${source.name}"))
  }
}

## Exported PM declaration `load_remote_index_from`.
export proc load_remote_index_from(index_path: Path) [fs, error] -> Result[List[types.RemotePackage]] {
  if fs.exists(index_path)? {
    let rows: List[Record] = json.read(index_path)?
    return decode_remote_index(rows)
  }

  let empty = []
  empty
}

proc try_load_remote_index_from_repo(repo: Str, out: Path) [fs, net, error] -> Result[List[types.RemotePackage]] {
  if util.is_file_url(repo) {
    return load_remote_index_from(util.repo_file_path(repo, p"index.json")?)?
  }

  # The mirror advertises a cache lifetime for index.json; PM needs the current generation.
  let response = net.request({
    method: "GET",
    url: util.repo_url_for(repo, p"index.json")?,
    headers: [{name: "Cache-Control", value: "no-cache"}, {name: "Pragma", value: "no-cache"}],
    pool: "pm",
    timeout: 15s,
    connect_timeout: 5s,
    max_body_bytes: 10485760,
  })?

  if response.status == 404 {
    let empty = []
    return empty
  }

  if response.status < 200 or response.status >= 300 {
    return Err(types.PmError.RemoteIndex(f"failed to fetch remote index: HTTP ${response.status}"))
  }

  let body = response.body.utf8()?
  let rows: List[Record] = json.decode(body)?
  let items = decode_remote_index(rows)?
  fs.mkdir(out)?
  fs.write_atomic(util.remote_index_cache_path(out), body)?
  items
}

## Exported PM declaration `load_remote_index_from_repo`.
export proc load_remote_index_from_repo(
  repo: Str,
  out: Path,
) [fs, net, time, error] -> Result[List[types.RemotePackage]] {
  if util.is_file_url(repo) {
    return try_load_remote_index_from_repo(repo, out)?
  }

  retry [1s, 2s, 4s, 15s, 60s] {
    try_load_remote_index_from_repo(repo, out)?
  }?
}

## Exported PM declaration `decode_remote_index`.
export proc decode_remote_index(rows: List[Record]) [error] -> Result[List[types.RemotePackage]] {
  var items = [decode_remote_package(row)? for row in rows]
  items
}

## Exported PM declaration `decode_remote_package`.
export proc decode_remote_package(row: Record) [error] -> Result[types.RemotePackage] {
  var arch = "aarch64"
  let empty_mkdeps_target = []
  let mkdeps_host = if row.has("mkdeps_host") { row.get("mkdeps_host")? } else { row.get("mkdeps")? }

  let mkdeps_target = if row.has("mkdeps_target") {
    row.get("mkdeps_target")?
  } else if row.has("target_build_deps") {
    row.get("target_build_deps")?
  } else {
    empty_mkdeps_target
  }

  if row.has("arch") {
    let stored_arch: Str = row.get("arch")?
    arch = util.normalize_arch(stored_arch)
  }

  {
    arch,
    name: row.get("name")?,
    ver: row.get("ver")?,
    rel: row.get("rel")?,
    deps: row.get("deps")?,
    mkdeps_host,
    mkdeps_target,
    sha256: row.get("sha256")?,
    size: row.get("size")?,
    tarball: row.get("tarball")?,
    metadata: if row.has("metadata") { row.get("metadata")? } else { "" },
    metadata_sha256: if row.has("metadata_sha256") { row.get("metadata_sha256")? } else { "" },
    artifact_key: if row.has("artifact_key") { row.get("artifact_key")? } else { "" },
    recipe_sha256: if row.has("recipe_sha256") { row.get("recipe_sha256")? } else { "" },
    executor_sha256: if row.has("executor_sha256") { row.get("executor_sha256")? } else { "" },
    proof_key: if row.has("proof_key") { row.get("proof_key")? } else { "" },
    proof_sha256: if row.has("proof_sha256") { row.get("proof_sha256")? } else { "" },
    proof: if row.has("proof") { row.get("proof")? } else { "" },
    proof_receipt_sha256: if row.has("proof_receipt_sha256") { row.get("proof_receipt_sha256")? } else { "" },
    source_sha256: row.get("source_sha256")?,
    metapackage: row.get("metapackage")?,
  }
}

## Exported PM declaration `load_cached_remote_index`.
export proc load_cached_remote_index(out: Path) [fs, error] -> Result[List[types.RemotePackage]] {
  load_remote_index_from(util.remote_index_cache_path(out))?
}

## Exported PM declaration `write_remote_index_cache`.
export proc write_remote_index_cache(out: Path, index: List[types.RemotePackage]) [fs, error] {
  fs.mkdir(out)?
  json.write(util.remote_index_cache_path(out), index)?
}

## Exported PM declaration `write_remote_index_to_repo`.
export proc write_remote_index_to_repo(
  repo: Str,
  work: Path,
  out: Path,
  index: List[types.RemotePackage],
  token: Str,
) [fs, net, error] {
  write_remote_index_cache(out, index)?

  if util.is_file_url(repo) {
    let dest = util.repo_file_path(repo, p"index.json")?
    let temporary = fp"${dest.parent}/.${dest.name}.tmp"
    fs.mkdir(dest.parent)?
    fs.remove(temporary, missing_ok: true)?
    defer fs.remove(temporary, missing_ok: true)?
    fs.copy(util.remote_index_cache_path(out), temporary, overwrite: true)?
    fs.rename(temporary, dest, overwrite: true)?
    return
  }

  upload_repo_file(repo, p"index.json", util.remote_index_cache_path(out), token, work)?
}

proc merge_remote_indexes(
  base: List[types.RemotePackage],
  overlay: List[types.RemotePackage],
) [error] -> Result[List[types.RemotePackage]] {
  var merged = base

  for entry in overlay {
    merged = upsert_remote_package(merged, entry)?
  }

  merged
}

## Exported PM declaration `refresh_remote_index`.
export proc refresh_remote_index(out: Path) [fs, net, env, time, error] -> Result[List[types.RemotePackage]] {
  let repo_urls = load_repo_urls()?
  var fetched = false
  var index = []

  if repo_urls.public_repo != "" {
    index = merge_remote_indexes(index, load_remote_index_from_repo(repo_urls.public_repo, out)?)?
    fetched = true
  }

  if repo_urls.repo != "" and repo_urls.repo != repo_urls.public_repo {
    index = merge_remote_indexes(index, load_remote_index_from_repo(repo_urls.repo, out)?)?
    fetched = true
  }

  if ! fetched {
    if fs.exists(util.remote_index_cache_path(out))? {
      let cached = load_cached_remote_index(out)?
      print "remote-index" cached.len() "cached"
      return cached
    }

    return Err(types.PmError.RemoteRepo("set XSH_PM_PUBLIC_REPO, R2_PUBLIC_URL, XSH_PM_REPO, or LAPUTA_REPO"))
  }

  write_remote_index_cache(out, index)?
  print "remote-index" index.len() "refreshed"
  index
}

## Exported PM declaration `ensure_remote_index`.
export proc ensure_remote_index(out: Path) [fs, net, env, time, error] -> Result[List[types.RemotePackage]] {
  if fs.exists(util.remote_index_cache_path(out))? {
    return load_cached_remote_index(out)?
  }

  refresh_remote_index(out)?
}

## Exported PM declaration `upsert_remote_package`.
export proc upsert_remote_package(
  index: List[types.RemotePackage],
  entry: types.RemotePackage,
) [error] -> Result[List[types.RemotePackage]] {
  var updated = []
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

## Exported PM declaration `find_remote_package`.
export proc find_remote_package(
  index: List[types.RemotePackage],
  name: Str,
) [env, error] -> Result[types.RemotePackage] {
  let arch = util.machine_arch()?

  for entry in index {
    if entry.arch == arch and entry.name == name {
      return entry
    }
  }

  return Err(types.PmError.RemotePackage(f"${name} for ${arch} is not in the remote index"))
}

## Exported PM declaration `collect_remote_packages`.
export proc collect_remote_packages(
  root: Path,
  index: List[types.RemotePackage],
  names: List[Str],
) [fs, env, error] -> Result[List[types.RemotePackage]] {
  var packages = []
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
        if ! fs.exists(util.package_db_path(root, dep))? and ! seen.get(dep, false) {
          pending = pending.push(dep)
        }
      }
    }
  }

  packages
}

## Exported PM declaration `order_remote_packages`.
export proc order_remote_packages(
  root: Path,
  packages: List[types.RemotePackage],
) [fs, error] -> Result[List[types.RemotePackage]] {
  var ordered = []
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
            if ! fs.exists(util.package_db_path(root, dep))? {
              return Err(types.PmError.MissingDependency(f"${pkg.name} depends on missing ${dep}"))
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
      return Err(types.PmError.DependencyCycle("remote package dependency graph did not make progress"))
    }
  }

  ordered
}

## Exported PM declaration `verify_cached_tarball`.
export proc verify_cached_tarball(tarball: Path, pkg: types.RemotePackage) [fs, error] -> Result[Bool] {
  if ! fs.exists(tarball)? {
    return false
  }

  if pkg.sha256 != "" and hash.sha256(tarball)?.hex() != pkg.sha256 {
    fs.remove(tarball, missing_ok: true)?
    return false
  }

  true
}

## Exported PM declaration `downloaded_tarball_failure`.
export proc downloaded_tarball_failure(tarball: Path, pkg: types.RemotePackage, url: Str) [fs, error] -> Result[Str] {
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

## Exported PM declaration `download_remote_tarball`.
export proc download_remote_tarball(out: Path, pkg: types.RemotePackage) [fs, net, env, time, error] -> Result[Record] {
  let tarball = util.remote_cache_tarball_path(out, pkg)?

  if verify_cached_tarball(tarball, pkg)? {
    return {tarball, from_cache: true}
  }

  let repo_urls = load_repo_urls()?
  var fetched = false
  var failures = []

  if repo_urls.public_repo != "" {
    let rel = fp"${pkg.tarball}"
    let url = util.repo_url_for(repo_urls.public_repo, rel)?
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
    let url = util.repo_url_for(repo_urls.repo, rel)?
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

  return Err(types.PmError.RemoteFetch(f"failed to fetch ${pkg.name} ${util.version_id(pkg.ver, pkg.rel)}: ${detail}"))
}

## Exported PM declaration `fetch_remote_metadata_sidecar`.
export proc fetch_remote_metadata_sidecar(
  out: Path,
  pkg: types.RemotePackage,
) [fs, net, env, time, error] -> Result[Record] {
  let metadata = util.remote_cache_metadata_path(out, pkg)?

  if pkg.metadata == "" {
    return {found: false, path: metadata, from_cache: false}
  }

  if fs.exists(metadata)? {
    return {found: true, path: metadata, from_cache: true}
  }

  let rel = util.ensure_relative_path(fp"${pkg.metadata}", "remote metadata")?
  let repo_urls = load_repo_urls()?
  var fetched = false
  var failures = []

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
      types.PmError.RemoteFetch(
        f"failed to fetch metadata for ${pkg.name} ${util.version_id(pkg.ver, pkg.rel)}: ${failures.join("; ")}",
      ),
    )
  }

  return {found: false, path: metadata, from_cache: false}
}

## Exported PM declaration `package_from_remote`.
export pure package_from_remote(pkg: types.RemotePackage) -> Result[types.Package] {
  {
    dir: p".",
    name: pkg.name,
    ver: pkg.ver,
    rel: pkg.rel,
    kind: if pkg.metapackage { types.package_meta() } else { types.package_payload() },
    deps: pkg.deps,
    mkdeps_host: pkg.mkdeps_host,
    mkdeps_target: pkg.mkdeps_target,
    upstream_sources: [],
    filetree: [],
    nostrip: false,
    source_mirror: false,
  }
}

## Exported PM declaration `remote_entry_for`.
export pure remote_entry_for(
  arch: Str,
  pkg: types.Package,
  tarball_rel: Str,
  sha256: Str,
  size: Int,
  metadata_rel: Str,
  source_sha256: Str,
  metapackage: Bool,
) -> types.RemotePackage {
  return {
    arch,
    name: pkg.name,
    ver: pkg.ver,
    rel: pkg.rel,
    deps: pkg.deps,
    mkdeps_host: pkg.mkdeps_host,
    mkdeps_target: pkg.mkdeps_target,
    sha256,
    size,
    tarball: tarball_rel,
    metadata: metadata_rel,
    metadata_sha256: "",
    artifact_key: "",
    recipe_sha256: "",
    executor_sha256: "",
    proof_key: "",
    proof_sha256: "",
    proof: "",
    proof_receipt_sha256: "",
    source_sha256,
    metapackage,
  }
}

## Derives the legacy retrieval fingerprint kept for index rows that predate immutable metadata sidecars.
export pure legacy_snapshot_digest(value: types.RemotePackage) -> Str {
  var lines = [
    "format\tlaputa-legacy-remote-entry-1",
    f"arch\t${value.arch}",
    f"name\t${value.name}",
    f"ver\t${value.ver}",
    f"rel\t${value.rel}",
    f"sha256\t${value.sha256}",
    f"tarball\t${value.tarball}",
    f"metadata\t${value.metadata}",
    f"source-sha256\t${value.source_sha256}",
    f"metapackage\t${value.metapackage}",
  ]

  for dependency in value.deps |> sort {
    lines = lines.push(f"runtime\t${dependency}")
  }

  for dependency in value.mkdeps_host |> sort {
    lines = lines.push(f"build-host\t${dependency}")
  }

  for dependency in value.mkdeps_target |> sort {
    lines = lines.push(f"build-target\t${dependency}")
  }

  bytes.from_text(lines.join("\n") + "\n").sha256().hex()
}

## Decodes new immutable index identities while retaining the legacy empty-identity fallback.
export proc plan_artifact_from_package(value: types.RemotePackage) [error] -> Result[types.RemotePlanArtifact] {
  let fields = [value.artifact_key, value.recipe_sha256, value.executor_sha256, value.proof_key, value.proof_sha256]
  let populated = [field for field in fields if field != ""]

  if populated.len() != 0 and populated.len() != fields.len() {
    return Err(types.PmError.PackageContract(f"remote package ${value.name} has a partial immutable identity"))
  }

  let fallback = legacy_snapshot_digest(value)
  let tarball = if value.tarball == "" {
    util.remote_binary_rel(value.arch, value.name, value.ver, value.rel).display()
  } else {
    value.tarball
  }
  let metadata = if value.metadata == "" {
    util.remote_metadata_rel(value.arch, value.name, value.ver, value.rel).display()
  } else {
    value.metadata
  }

  {
    name: value.name,
    ver: value.ver,
    rel: value.rel,
    retrieval: {
      arch: value.arch,
      tarball,
      tarball_sha256: if value.sha256 == "" { fallback } else { value.sha256 },
      metadata,
      metadata_sha256: if value.metadata_sha256 == "" { fallback } else { value.metadata_sha256 },
    },
    artifact_key: value.artifact_key,
    recipe_sha256: value.recipe_sha256,
    executor_sha256: value.executor_sha256,
    proof_key: value.proof_key,
    proof_sha256: value.proof_sha256,
  }
}

proc remote_legacy_metadata_rel(value: types.RemotePackage) [error] -> Result[Path] {
  let raw = if value.metadata == "" {
    util.remote_metadata_rel(value.arch, value.name, value.ver, value.rel).display()
  } else {
    value.metadata
  }

  util.ensure_relative_path(fp"${raw}", f"remote metadata for ${value.name}")?
}

## Resolves the omitted metadata hash in a legacy index into the exact retrieval bytes recorded in a BuildPlan.
## Modern rows already carry that digest and require no additional request.
export proc plan_artifact_from_package_at_repo(
  value: types.RemotePackage,
  repo: Str,
  cache: Path,
) [fs, net, error] -> Result[types.RemotePlanArtifact] {
  if value.metadata_sha256 != "" {
    return plan_artifact_from_package(value)?
  }

  if repo == "" {
    return Err(types.PmError.RemoteRepo(f"legacy remote package ${value.name} needs a repository URL to hash its metadata"))
  }

  let rel = remote_legacy_metadata_rel(value)?
  let cache_path = fp"${cache}/legacy-metadata/${bytes.from_text(rel.display()).sha256().hex()}.json"
  let failure = try_fetch_repo_file(repo, rel, cache_path)?

  if failure != "" {
    return Err(types.PmError.RemoteFetch(failure))
  }

  let metadata_sha256 = hash.sha256(cache_path)?.hex()
  plan_artifact_from_package({...value, metadata: rel.display(), metadata_sha256})?
}

## Exported PM declaration `upload_package_source`.
export proc upload_package_source(
  repo: Str,
  work: Path,
  out: Path,
  pkg: types.Package,
  token: Str,
) [fs, net, env, time, error] -> Result[types.UploadedSource] {
  let arch = util.machine_arch()?
  let mirror = util.source_mirror_path_for_arch(out, pkg, arch)

  if ! fs.exists(mirror)? {
    return {rel: "", sha256: ""}
  }

  let rel = util.remote_source_rel_for_arch(arch, pkg.name, pkg.ver, pkg.rel)
  let metadata = fs.metadata(mirror)?

  if metadata.size > 52428800 {
    upload_large_repo_file(repo, rel, mirror, token, work)?
  } else {
    upload_repo_file(repo, rel, mirror, token, work)?
  }

  {rel: rel.display(), sha256: hash.sha256(mirror)?.hex()}
}
