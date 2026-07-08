use extensions
use local
use remote
use types
use util

export proc stage_built_package(
  repo_dir: Path,
  upload_ctx: PmContext,
  index: List[RemotePackage],
  item: BuiltPackage,
) [fs, process, env, error] -> Result[List[RemotePackage]] {
  let arch = machine_arch()?
  let tarball_rel = remote_binary_rel(arch, item.pkg.name, item.pkg.ver, item.pkg.rel)
  let metadata_rel = remote_metadata_rel(arch, item.pkg.name, item.pkg.ver, item.pkg.rel)
  let dest = fp"${repo_dir}/${tarball_rel}"
  let metadata_dest = fp"${repo_dir}/${metadata_rel}"
  fs.mkdir(dest.parent)?
  fs.copy(item.tarball, dest, overwrite: true)?
  write_package_metadata(metadata_dest, arch, item)?
  let tarball_metadata = fs.metadata(item.tarball)?

  let entry = remote_entry_for(
    arch,
    item.pkg,
    tarball_rel.display(),
    hash.sha256(item.tarball)?.hex(),
    tarball_metadata.size,
    metadata_rel.display(),
    "",
    "",
    false,
  )

  let updated = upsert_remote_package(index, entry)?
  run_lifecycle_hooks("post-upload", item.pkg.name, upload_ctx, "")?
  print --flush ${item.pkg.name} version_id(item.pkg.ver, item.pkg.rel) "stage:" "done"
  updated
}

export proc upload_repo_export_file(repo: Str, rel: Path, source: Path, token: Str, work: Path) [fs, net, time, error] {
  let metadata = fs.metadata(source)?

  if metadata.size > 52428800 {
    upload_large_repo_file(repo, rel, source, token, work)?
  } else {
    upload_repo_file(repo, rel, source, token, work)?
  }
}

proc remote_export_entry_same(remote_index: List[RemotePackage], entry: RemotePackage) [] -> Bool {
  for rpkg in remote_index {
    if rpkg.arch == entry.arch and rpkg.name == entry.name {
      return rpkg.ver == entry.ver and rpkg.rel == entry.rel and rpkg.deps == entry.deps and rpkg.mkdeps == entry.mkdeps and rpkg.target_build_deps == entry.target_build_deps and rpkg.sha256 == entry.sha256 and rpkg.size == entry.size and rpkg.tarball == entry.tarball and rpkg.metadata == entry.metadata and rpkg.source_sha256 == entry.source_sha256 and rpkg.source_tarball == entry.source_tarball and rpkg.metapackage == entry.metapackage
    }
  }

  false
}

export proc upload_repo_export(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 2 {
    return Err(PmError.Usage("usage: pm upload-repo-export REPO_DIR"))
  }

  let repo_dir = path.absolute(fp"${argv[1]}")?
  let index_path = fp"${repo_dir}/index.json"
  let work = fp"${repo_dir}/.upload-work"
  let out = fp"${repo_dir}/.upload-out"
  let root = fp"${repo_dir}/.upload-root"
  let repo_urls = require_repo_url()?
  let token = require_auth_token(root)?
  let repo = repo_urls.repo
  var remote_index = load_remote_index_from_repo(repo, out)?
  let export_index = load_remote_index_from(index_path)?
  fs.mkdir(work)?
  fs.mkdir(out)?

  for entry in export_index {
    if remote_export_entry_same(remote_index, entry) {
      print ${entry.arch} ${entry.name} version_id(entry.ver, entry.rel) "already-exported"
      continue
    }

    var uploaded = entry

    if ! entry.metapackage {
      if entry.tarball == "" {
        return Err(PmError.PackageTarball(f"${entry.name} ${version_id(entry.ver, entry.rel)} has no tarball"))
      }

      let tarball_rel = ensure_relative_path(fp"${entry.tarball}", "remote tarball")?
      let tarball = fp"${repo_dir}/${tarball_rel.display()}"

      if ! fs.exists(tarball)? {
        return Err(PmError.PackageTarball(f"${tarball.display()} is missing"))
      }

      upload_repo_export_file(repo, tarball_rel, tarball, token, work)?
      let tarball_metadata = fs.metadata(tarball)?
      uploaded = {...uploaded, sha256: hash.sha256(tarball)?.hex(), size: tarball_metadata.size}

      if entry.metadata != "" {
        let metadata_rel = ensure_relative_path(fp"${entry.metadata}", "remote metadata")?
        let metadata = fp"${repo_dir}/${metadata_rel.display()}"

        if ! fs.exists(metadata)? {
          return Err(PmError.PackageTarball(f"${metadata.display()} is missing"))
        }

        upload_repo_export_file(repo, metadata_rel, metadata, token, work)?
      }
    }

    let source = fp"${repo_dir}/.out/source-mirrors/${package_id(entry.name, entry.ver, entry.rel)}-${entry.arch}.tar.gz"

    if fs.exists(source)? {
      let source_rel = remote_source_rel_for_arch(entry.arch, entry.name, entry.ver, entry.rel)
      upload_repo_export_file(repo, source_rel, source, token, work)?
      uploaded = {...uploaded, source_sha256: hash.sha256(source)?.hex(), source_tarball: source_rel.display()}
    }

    remote_index = upsert_remote_package(remote_index, uploaded)?
    print ${entry.arch} ${entry.name} version_id(entry.ver, entry.rel) "exported"
  }

  write_remote_index_to_repo(repo, work, out, remote_index, token)?
  print "repo" export uploaded
}
