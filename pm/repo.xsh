use build as pm_build
use buildroot
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

proc order_repo_build_packages(
  root: Path,
  packages: List[Package],
  index: List[RemotePackage],
) [fs, env, error] -> Result[List[Package]] {
  var ordered = []
  var by_name: Map[Int] = {}
  var pkg_index = 0

  for pkg in packages {
    by_name[pkg.name] = pkg_index
    pkg_index += 1
  }

  var repo_names: Map[Bool] = {}
  let arch = machine_arch()?

  for item in index {
    if item.arch == arch {
      repo_names[item.name] = true
    }
  }

  var added: Map[Bool] = {}

  while ordered.len() < packages.len() {
    var progressed = false

    for pkg in packages {
      if ! added.get(pkg.name, false) {
        var ready = true

        for dep in pkg.deps {
          if ! by_name.has(dep) {
            if ! repo_names.get(dep, false) and ! fs.exists(package_db_path(root, dep))? {
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
      return Err(PmError.DependencyCycle("package dependency graph did not make progress"))
    }
  }

  ordered
}

export proc upload_set_repo(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 3 {
    return Err(PmError.Usage("usage: pm upload-set REPO_DIR PKGDIR..."))
  }

  let repo_dir = path.absolute(fp"${argv[1]}")?
  let build_root = fp"${repo_dir}/.set-build-root"
  let work = fp"${repo_dir}/.work"
  let out = fp"${repo_dir}/.out"
  let upload_ctx: PmContext = {command: "upload", root: build_root, work, out}
  var raw_args = []
  var build_i = 2

  while build_i < argv.len() {
    raw_args = raw_args.push(argv[build_i])
    build_i += 1
  }

  fs.mkdir(work)?
  fs.mkdir(out)?
  let lock = fs.lock(fp"${work}/pm.lock")?
  defer fs.unlock(lock)?
  let packages = load_package_dirs(paths_from_args(raw_args)?)?

  for pkg in packages {
    upload_package(upload_ctx, pkg)?
  }
}

export proc build_repo(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 3 {
    return Err(PmError.Usage("usage: pm build REPO_DIR PKGDIR..."))
  }

  let repo_dir = path.absolute(fp"${argv[1]}")?
  let build_work = fp"${repo_dir}/.work"
  let build_out = fp"${repo_dir}/.out"
  let build_root = fp"${repo_dir}/.root"
  let ctx: PmContext = {command: "build", root: build_root, work: build_work, out: build_out}
  let upload_ctx: PmContext = {...ctx, command: "upload"}
  fs.mkdir(repo_dir)?
  var raw_args = []
  var build_i = 2

  while build_i < argv.len() {
    raw_args = raw_args.push(argv[build_i])
    build_i += 1
  }

  let index_path = fp"${repo_dir}/index.json"
  var index = []

  if fs.exists(index_path)? {
    index = load_remote_index_from(index_path)?
  }

  let packages = load_package_dirs(paths_from_args(raw_args)?)?
  let local_names = local_package_names(packages)
  install_remote_dependency_set(ctx, missing_dependency_names(build_root, packages, true, local_names)?)?
  let ordered = order_repo_build_packages(build_root, packages, index)?
  let built = pm_build.build_packages(ctx, ordered)?

  for item in built {
    index = stage_built_package(repo_dir, upload_ctx, index, item)?
  }

  json.write(index_path, index)?
}

export proc upload_package(ctx: PmContext, pkg: Package) [fs, net, process, env, time, error] {
  let repo_urls = require_repo_url()?
  let token = require_auth_token(ctx.root)?
  run_lifecycle_hooks("pre-upload", pkg.name, ctx, "")?
  let repo = repo_urls.repo
  let arch = machine_arch()?
  var index = load_remote_index_from_repo(repo, ctx.out)?

  if pkg.sources.len() == 0 {
    let entry = remote_entry_for(arch, pkg, "", "", 0, "", "", "", true)
    index = upsert_remote_package(index, entry)?
    write_remote_index_to_repo(repo, ctx.work, ctx.out, index, token)?
    run_lifecycle_hooks("post-upload", pkg.name, ctx, "metapackage")?
    print ${pkg.name} version_id(pkg.ver, pkg.rel) "staged"
    return
  }

  let tarball = fp"${ctx.out}/${remote_tarball_name(pkg.name, pkg.ver, pkg.rel)}"

  if ! fs.exists(tarball)? {
    return Err(PmError.PackageTarball(f"${tarball.display()} is missing; build before upload"))
  }

  let tarball_rel = remote_binary_rel(arch, pkg.name, pkg.ver, pkg.rel)
  let tarball_metadata = fs.metadata(tarball)?

  if tarball_metadata.size > 52428800 {
    upload_large_repo_file(repo, tarball_rel, tarball, token, ctx.work)?
  } else {
    upload_repo_file(repo, tarball_rel, tarball, token, ctx.work)?
  }

  let id = package_id(pkg.name, pkg.ver, pkg.rel)
  let metadata_stage = fp"${ctx.work}/${id}-metadata"
  fs.remove(metadata_stage, missing_ok: true)?
  fs.mkdir(metadata_stage)?
  archive.tar_extract(tarball, metadata_stage, 0, "auto", true)?
  let built = load_built_package_from_dest(pkg, id, tarball, metadata_stage)?
  let metadata_rel = remote_metadata_rel(arch, pkg.name, pkg.ver, pkg.rel)
  let metadata_path = fp"${ctx.out}/${metadata_rel}"
  write_package_metadata(metadata_path, arch, built)?
  upload_repo_file(repo, metadata_rel, metadata_path, token, ctx.work)?
  let uploaded_source = upload_package_source(repo, ctx.work, ctx.out, pkg, token)?

  let entry = remote_entry_for(
    arch,
    pkg,
    tarball_rel.display(),
    hash.sha256(tarball)?.hex(),
    tarball_metadata.size,
    metadata_rel.display(),
    uploaded_source.rel,
    uploaded_source.sha256,
    false,
  )

  index = upsert_remote_package(index, entry)?
  write_remote_index_to_repo(repo, ctx.work, ctx.out, index, token)?
  run_lifecycle_hooks("post-upload", pkg.name, ctx, "")?
  print ${pkg.name} version_id(pkg.ver, pkg.rel) "uploaded"

  if uploaded_source.rel != "" {
    print ${pkg.name} source uploaded
  }
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
