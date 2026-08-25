##! PM repo operations and shared package-manager policy.
use build as pm_build
use buildroot
use catalog
use extensions
use graph
use local
use policy
use remote
use types
use util

## Exported PM declaration `stage_built_package`.
export proc stage_built_package(
  repo_dir: Path,
  upload_ctx: types.PmContext,
  index: List[types.RemotePackage],
  item: types.BuiltPackage,
) [fs, process, env, error] -> Result[List[types.RemotePackage]] {
  let arch = util.machine_arch()?
  let tarball_rel = util.remote_binary_rel(arch, item.pkg.name, item.pkg.ver, item.pkg.rel)
  let metadata_rel = util.remote_metadata_rel(arch, item.pkg.name, item.pkg.ver, item.pkg.rel)
  let dest = fp"${repo_dir}/${tarball_rel}"
  let metadata_dest = fp"${repo_dir}/${metadata_rel}"
  fs.mkdir(dest.parent)?
  fs.copy(item.tarball, dest, overwrite: true)?
  local.write_package_metadata(metadata_dest, arch, item)?
  let tarball_metadata = fs.metadata(item.tarball)?

  let entry = remote.remote_entry_for(
    arch,
    item.pkg,
    tarball_rel.display(),
    hash.sha256(item.tarball)?.hex(),
    tarball_metadata.size,
    metadata_rel.display(),
    "",
    false,
  )

  let updated = remote.upsert_remote_package(index, entry)?
  extensions.run_lifecycle_hooks("post-upload", item.pkg.name, upload_ctx, "")?
  print --flush ${item.pkg.name} util.version_id(item.pkg.ver, item.pkg.rel) "stage:" "done"
  updated
}

proc order_repo_build_packages(
  root: Path,
  packages: List[types.Package],
  index: List[types.RemotePackage],
) [fs, env, error] -> Result[List[types.Package]] {
  let arch = util.machine_arch()?
  let remote_names = remote.selected_snapshot_names(index, arch)
  var local_names: Map[Bool] = {}
  var available_names = remote_names

  for pkg in packages {
    local_names[pkg.name] = true
  }

  for pkg in packages {
    for dependency in pkg.deps {
      if ! local_names.get(dependency, false) {
        if dependency not in remote_names and ! fs.exists(util.package_db_path(root, dependency))? {
          return Err(types.PmError.MissingDependency(f"${pkg.name} depends on missing ${dependency}"))
        }

        available_names = available_names.push(dependency)
      }
    }

    for dependency in pkg.mkdeps_host.extend(pkg.mkdeps_target) {
      if ! local_names.get(dependency, false) {
        available_names = available_names.push(dependency)
      }
    }
  }

  let local_catalog = catalog.from_packages(root, packages, available_names)?
  let value = remote.catalog_with_selected_snapshot(local_catalog, index, arch)?
  let edges = graph.edges(value, policy.aarch64_docker())?
  let runtime_edges = [edge for edge in edges if edge.kind == types.Runtime]
  let levels = graph.topological_levels(catalog.package_names(value), runtime_edges)?
  let by_name = catalog.package_map(value)
  var ordered: List[types.Package] = []

  for level in levels {
    for name in level {
      if by_name.has(name) {
        let pkg: types.Package = by_name.get(name)?
        ordered = ordered.push(pkg)
      }
    }
  }

  ordered
}

proc verify_proof_receipt(out: Path, pkg: types.Package, tarball: Path) [fs, error] {
  let receipt = util.proof_receipt_path(out, pkg)

  if ! fs.exists(receipt)? {
    return Err(
      types.PmError.PackageTarball(f"${pkg.name} has no successful proof receipt; build and prove it before upload"),
    )
  }

  let metadata: Record = json.read(receipt)?
  let expected: Str = metadata.get("tarball_sha256")?
  let actual = hash.sha256(tarball)?.hex()

  if expected != actual {
    return Err(types.PmError.PackageTarball(f"${pkg.name} proof receipt does not match the package tarball"))
  }
}

## Exported PM declaration `upload_set_repo`.
export proc upload_set_repo(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 3 {
    return Err(types.PmError.Usage("usage: pm upload-set REPO_DIR PKGDIR..."))
  }

  let repo_dir = path.absolute(fp"${argv[1]}")?
  let build_root = fp"${repo_dir}/.set-build-root"
  let work = fp"${repo_dir}/.work"
  let out = fp"${repo_dir}/.out"
  let upload_ctx: types.PmContext = {command: "upload", root: build_root, work, out}
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
  let packages = local.load_package_dirs(util.paths_from_args(raw_args)?)?

  for pkg in packages {
    upload_package(upload_ctx, pkg)?
  }
}

## Exported PM declaration `build_repo`.
export proc build_repo(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 3 {
    return Err(types.PmError.Usage("usage: pm build REPO_DIR PKGDIR..."))
  }

  let repo_dir = path.absolute(fp"${argv[1]}")?
  let build_work = fp"${repo_dir}/.work"
  let build_out = fp"${repo_dir}/.out"
  let build_root = fp"${repo_dir}/.root"
  let ctx: types.PmContext = {command: "build", root: build_root, work: build_work, out: build_out}
  let upload_ctx: types.PmContext = {...ctx, command: "upload"}
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
    index = remote.load_remote_index_from(index_path)?
  }

  let packages = local.load_package_dirs(util.paths_from_args(raw_args)?)?
  let local_names = buildroot.local_package_names(packages)
  buildroot.install_remote_dependency_set(
    ctx,
    buildroot.missing_dependency_names(build_root, packages, true, local_names)?,
  )?
  let ordered = order_repo_build_packages(build_root, packages, index)?
  let built = pm_build.build_packages(ctx, ordered)?

  for item in built {
    index = stage_built_package(repo_dir, upload_ctx, index, item)?
  }

  json.write(index_path, index)?
}

## Exported PM declaration `upload_package`.
export proc upload_package(ctx: types.PmContext, pkg: types.Package) [fs, net, process, env, time, error] {
  let repo_urls = remote.require_repo_url()?
  let token = remote.require_auth_token(ctx.root)?
  extensions.run_lifecycle_hooks("pre-upload", pkg.name, ctx, "")?
  let repo = repo_urls.repo
  let arch = util.machine_arch()?
  var index = remote.load_remote_index_from_repo(repo, ctx.out)?

  if pkg.kind == types.Meta {
    let entry = remote.remote_entry_for(arch, pkg, "", "", 0, "", "", true)
    index = remote.upsert_remote_package(index, entry)?
    remote.write_remote_index_to_repo(repo, ctx.work, ctx.out, index, token)?
    extensions.run_lifecycle_hooks("post-upload", pkg.name, ctx, "metapackage")?
    print ${pkg.name} util.version_id(pkg.ver, pkg.rel) "staged"
    return
  }

  let tarball = fp"${ctx.out}/${util.remote_tarball_name(pkg.name, pkg.ver, pkg.rel)}"

  if ! fs.exists(tarball)? {
    return Err(types.PmError.PackageTarball(f"${tarball.display()} is missing; build before upload"))
  }

  verify_proof_receipt(ctx.out, pkg, tarball)?
  let tarball_rel = util.remote_binary_rel(arch, pkg.name, pkg.ver, pkg.rel)
  let tarball_metadata = fs.metadata(tarball)?

  if tarball_metadata.size > 52428800 {
    remote.upload_large_repo_file(repo, tarball_rel, tarball, token, ctx.work)?
  } else {
    remote.upload_repo_file(repo, tarball_rel, tarball, token, ctx.work)?
  }

  let id = util.package_id(pkg.name, pkg.ver, pkg.rel)
  let metadata_stage = fp"${ctx.work}/${id}-metadata"
  fs.remove(metadata_stage, missing_ok: true)?
  fs.mkdir(metadata_stage)?
  archive.tar_extract(tarball, metadata_stage, 0, "auto", true)?
  let built = local.load_built_package_from_dest(pkg, id, tarball, metadata_stage)?
  let metadata_rel = util.remote_metadata_rel(arch, pkg.name, pkg.ver, pkg.rel)
  let metadata_path = fp"${ctx.out}/${metadata_rel}"
  local.write_package_metadata(metadata_path, arch, built)?
  remote.upload_repo_file(repo, metadata_rel, metadata_path, token, ctx.work)?
  let uploaded_source = remote.upload_package_source(repo, ctx.work, ctx.out, pkg, token)?

  let entry = remote.remote_entry_for(
    arch,
    pkg,
    tarball_rel.display(),
    hash.sha256(tarball)?.hex(),
    tarball_metadata.size,
    metadata_rel.display(),
    uploaded_source.sha256,
    false,
  )

  index = remote.upsert_remote_package(index, entry)?
  remote.write_remote_index_to_repo(repo, ctx.work, ctx.out, index, token)?
  extensions.run_lifecycle_hooks("post-upload", pkg.name, ctx, "")?
  print ${pkg.name} util.version_id(pkg.ver, pkg.rel) "uploaded"

  if uploaded_source.rel != "" {
    print ${pkg.name} source uploaded
  }
}

## Exported PM declaration `upload_repo_export_file`.
export proc upload_repo_export_file(repo: Str, rel: Path, source: Path, token: Str, work: Path) [fs, net, time, error] {
  let metadata = fs.metadata(source)?

  if metadata.size > 52428800 {
    remote.upload_large_repo_file(repo, rel, source, token, work)?
  } else {
    remote.upload_repo_file(repo, rel, source, token, work)?
  }
}

proc export_entry_with_local_source(
  repo_dir: Path,
  entry: types.RemotePackage,
) [fs, error] -> Result[types.RemotePackage] {
  let source = fp"${repo_dir}/.out/source-mirrors/${util.package_id(entry.name, entry.ver, entry.rel)}-${entry.arch}.tar.bz2"

  if ! fs.exists(source)? {
    return entry
  }

  {...entry, source_sha256: hash.sha256(source)?.hex()}
}

proc remote_export_entry_same(remote_index: List[types.RemotePackage], entry: types.RemotePackage) [] -> Bool {
  for rpkg in remote_index {
    if rpkg.arch == entry.arch and rpkg.name == entry.name {
      return rpkg.ver == entry.ver and rpkg.rel == entry.rel and rpkg.deps == entry.deps and rpkg.mkdeps_host == entry.mkdeps_host and (rpkg.mkdeps_target.len() == 0 or rpkg.mkdeps_target == entry.mkdeps_target) and rpkg.sha256 == entry.sha256 and rpkg.size == entry.size and rpkg.tarball == entry.tarball and rpkg.metadata == entry.metadata and rpkg.source_sha256 == entry.source_sha256 and rpkg.metapackage == entry.metapackage
    }
  }

  false
}

## Exported PM declaration `upload_repo_export`.
export proc upload_repo_export(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 2 {
    return Err(types.PmError.Usage("usage: pm upload-repo-export REPO_DIR"))
  }

  let repo_dir = path.absolute(fp"${argv[1]}")?
  let index_path = fp"${repo_dir}/index.json"
  let work = fp"${repo_dir}/.upload-work"
  let out = fp"${repo_dir}/.upload-out"
  let root = fp"${repo_dir}/.upload-root"
  let repo_urls = remote.require_repo_url()?
  let token = remote.require_auth_token(root)?
  let repo = repo_urls.repo
  print --flush "repo-export" "loading" "remote index"
  var remote_index = remote.load_remote_index_from_repo(repo, out)?
  let export_index = remote.load_remote_index_from(index_path)?
  fs.mkdir(work)?
  fs.mkdir(out)?
  var pending = []

  for staged_entry in export_index {
    let entry = export_entry_with_local_source(repo_dir, staged_entry)?

    if remote_export_entry_same(remote_index, entry) {
      print --flush f"repo-export" ${entry.arch} ${entry.name} util.version_id(entry.ver, entry.rel) "already-exported"
    } else {
      pending = pending.push(entry)
    }
  }

  let uploaded_entries = pending
    |> par-map --jobs=4 { |entry|
      var uploaded = entry
      print --flush f"repo-export" ${entry.arch} ${entry.name} util.version_id(entry.ver, entry.rel) "uploading"

      if ! entry.metapackage {
        if entry.tarball == "" {
          return Err(
            types.PmError.PackageTarball(f"${entry.name} ${util.version_id(entry.ver, entry.rel)} has no tarball"),
          )
        }

        let tarball_rel = util.ensure_relative_path(fp"${entry.tarball}", "remote tarball")?
        let tarball = fp"${repo_dir}/${tarball_rel.display()}"

        if ! fs.exists(tarball)? {
          return Err(types.PmError.PackageTarball(f"${tarball.display()} is missing"))
        }

        let tarball_metadata = fs.metadata(tarball)?
        print --flush f"repo-export" ${entry.arch} ${entry.name} "uploading" "tarball" f"${tarball_metadata.size} bytes"
        upload_repo_export_file(repo, tarball_rel, tarball, token, work)?
        uploaded = {...uploaded, sha256: hash.sha256(tarball)?.hex(), size: tarball_metadata.size}

        if entry.metadata != "" {
          let metadata_rel = util.ensure_relative_path(fp"${entry.metadata}", "remote metadata")?
          let metadata = fp"${repo_dir}/${metadata_rel.display()}"

          if ! fs.exists(metadata)? {
            return Err(types.PmError.PackageTarball(f"${metadata.display()} is missing"))
          }

          let metadata_size = fs.metadata(metadata)?.size
          print --flush f"repo-export" ${entry.arch} ${entry.name} "uploading" "metadata" f"${metadata_size} bytes"
          upload_repo_export_file(repo, metadata_rel, metadata, token, work)?
        }
      }

      let source = fp"${repo_dir}/.out/source-mirrors/${util.package_id(entry.name, entry.ver, entry.rel)}-${entry.arch}.tar.bz2"

      if fs.exists(source)? {
        let source_rel = util.remote_source_rel_for_arch(entry.arch, entry.name, entry.ver, entry.rel)
        let source_size = fs.metadata(source)?.size
        print --flush f"repo-export" ${entry.arch} ${entry.name} "uploading" "source" f"${source_size} bytes"
        upload_repo_export_file(repo, source_rel, source, token, work)?
        uploaded = {...uploaded, source_sha256: hash.sha256(source)?.hex()}
      }

      uploaded
    }

  for uploaded in uploaded_entries {
    remote_index = remote.upsert_remote_package(remote_index, uploaded)?
    print --flush ${uploaded.arch} ${uploaded.name} util.version_id(uploaded.ver, uploaded.rel) "exported"
  }

  print --flush "repo-export" "writing" "remote index"
  remote.write_remote_index_to_repo(repo, work, out, remote_index, token)?
  print --flush "repo" export uploaded
}
