use extensions
use remote
use sources
use types
use util

export proc install_remote_metapackage(ctx: PmContext, pkg: RemotePackage) [fs, process, env, error] {
  let local_pkg = package_from_remote(pkg)?
  run_lifecycle_hooks("pre-install", pkg.name, ctx, "remote-metapackage")?
  write_package_db(ctx.root, local_pkg, [], [])?
  run_lifecycle_hooks("post-install", pkg.name, ctx, "remote-metapackage")?
  print ${pkg.name} version_id(pkg.ver, pkg.rel) "registered"
}

export proc install_remote_tarball(ctx: PmContext, pkg: RemotePackage, tarball: Path) [fs, process, env, error] {
  let id = package_id(pkg.name, pkg.ver, pkg.rel)
  let install_stage = fp"${ctx.work}/${id}-remote-install"
  fs.remove(install_stage, missing_ok: true)?
  fs.mkdir(install_stage)?
  archive.tar_extract(tarball, install_stage, 0, "auto", true)?
  let stage_db = package_db_path(install_stage, pkg.name)
  let manifest = load_manifest(stage_db)?
  let etcsums: List[EtcSum] = json.read(fp"${stage_db}/etcsums.json")?
  let local_pkg = package_with_extract_install(package_from_remote(pkg)?, load_extract_install(stage_db)?)
  let db = package_db_path(ctx.root, pkg.name)
  let old_manifest = load_manifest(db)?
  let old_sums = load_etcsums(db)?
  let new_sums = map_etcsums(etcsums)?
  let installed_owners = load_installed_owners(ctx.root)?

  if local_pkg.extract_install and ! fs.exists(db)? {
    run_lifecycle_hooks("pre-install", pkg.name, ctx, "remote-tarball")?
    direct_extract_package(ctx, local_pkg, tarball, manifest, etcsums, installed_owners)?
    run_lifecycle_hooks("post-install", pkg.name, ctx, "remote-tarball")?
    print ${pkg.name} manifest.len() "remote-installed"
    return
  }

  ensure_installable(ctx.root, local_pkg, manifest, installed_owners)?
  run_lifecycle_hooks("pre-install", pkg.name, ctx, "remote-tarball")?
  let old_manifest_extra = collect_old_manifest_extra(old_manifest, manifest)?

  if old_manifest_extra.len() > 0 {
    let _ = fs.remove_manifest(ctx.root, old_manifest_extra, missing_ok: true)?
  }

  install_manifest_entries(ctx.root, install_stage, local_pkg, manifest, old_sums, new_sums, installed_owners)?
  write_package_db(ctx.root, local_pkg, manifest, etcsums)?
  run_lifecycle_hooks("post-install", pkg.name, ctx, "remote-tarball")?
  print ${pkg.name} manifest.len() "remote-installed"
}

export proc install_remote_packages(ctx: PmContext, names: List[Str]) [fs, net, process, env, time, error] {
  let index = ensure_remote_index(ctx.out)?
  let selected = collect_remote_packages(ctx.root, index, names)?
  let ordered = order_remote_packages(ctx.root, selected)?
  let tarball_packages = ordered |> where ! .metapackage
  var tarballs: Map[Path] = {}

  if tarball_packages.len() > 0 {
    let downloaded = tarball_packages
      |> par-map --jobs=tarball_packages.len() { |pkg|
        let tarball = download_remote_tarball(ctx.out, pkg)?
        {name: pkg.name, tarball}
      }

    for item in downloaded {
      tarballs[item.name] = item.tarball
    }
  }

  for pkg in ordered {
    if pkg.metapackage {
      install_remote_metapackage(ctx, pkg)?
    } else {
      let tarball: Path = tarballs.get(pkg.name)?
      install_remote_tarball(ctx, pkg, tarball)?
    }
  }
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

export pure collect_manifest_text(manifest: List[Path]) -> Result[List[Str]] {
  let lines = [rel_path.display() for rel_path in manifest]
  lines
}

export proc load_manifest(db: Path) [fs, error] -> Result[List[Path]] {
  var manifest: List[Path] = []

  if fs.exists(fp"${db}/manifest.json")? {
    let stored: List[Str] = json.read(fp"${db}/manifest.json")?

    for rel_text in stored {
      manifest = manifest.push(Path.parse(rel_text)?)
    }
  }

  manifest
}

export proc map_etcsums(etcsums: List[EtcSum]) [error] -> Result[Map[Str]] {
  var mapped = {entry.path: entry.sha256 for entry in etcsums}
  mapped
}

export proc load_etcsums(db: Path) [fs, error] -> Result[Map[Str]] {
  var mapped: Map[Str] = {}

  if fs.exists(fp"${db}/etcsums.json")? {
    let rows: List[EtcSum] = json.read(fp"${db}/etcsums.json")?

    for row in rows {
      mapped[row.path] = row.sha256
    }
  }

  mapped
}

export proc load_metadata(db: Path) [fs, error] -> Result[Record] {
  let metadata: Record = json.read(fp"${db}/metadata.json")?
  metadata
}

export proc load_extract_install(db: Path) [fs, error] -> Result[Bool] {
  if ! fs.exists(fp"${db}/metadata.json")? {
    return false
  }

  let metadata = load_metadata(db)?

  if metadata.has("extract_install") {
    let extract_install: Bool = metadata.get("extract_install")?
    return extract_install
  }

  false
}

export pure package_with_extract_install(pkg: Package, extract_install: Bool) -> Package {
  {
    dir: pkg.dir,
    exports: pkg.exports,
    name: pkg.name,
    ver: pkg.ver,
    rel: pkg.rel,
    deps: pkg.deps,
    mkdeps: pkg.mkdeps,
    target_build_deps: pkg.target_build_deps,
    replaces: pkg.replaces,
    sources: pkg.sources,
    checksums: pkg.checksums,
    nostrip: pkg.nostrip,
    extract_install,
  }
}

export proc collect_old_manifest_extra(
  old_manifest: List[Path],
  new_manifest: List[Path],
) [error] -> Result[List[Path]] {
  var extra = [rel_path for rel_path in old_manifest if ! new_manifest.contains(rel_path)]
  extra
}

export proc collect_etcsums(dest: Path, manifest: List[Path]) [fs, error] -> Result[List[EtcSum]] {
  var sums: List[EtcSum] = []

  for rel_path in manifest {
    if is_etc_file(rel_path) {
      let meta = fs.metadata(fp"${dest}/${rel_path}")?

      if meta.kind == "file" {
        let sha256 = hash.sha256(fp"${dest}/${rel_path}")?.hex()
        sums = sums.push({path: rel_path.display(), sha256})
      }
    }
  }

  sums
}

export proc collect_metadata_files(root: Path, manifest: List[Path]) [fs, error] -> Result[List[Record]] {
  var files: List[Record] = []
  let root_handle = fs.open_root(root)?
  defer fs.close_root(root_handle)

  for rel_path in manifest {
    match fs.root_readlink(root_handle, rel_path) {
      Ok(target) => {
        files = files.push(
          {path: rel_path.display(), kind: "symlink", mode: 0o777, sha256: "", target: target.display()},
        )

        continue
      }
      Err(_) => {}
    }

    let meta = fs.root_metadata(root_handle, rel_path)?
    var sha256 = ""

    if meta.kind == "file" {
      sha256 = fs.root_read(root_handle, rel_path)?.sha256().hex()
    }

    files = files.push({path: rel_path.display(), kind: meta.kind, mode: meta.mode % 4096, sha256, target: ""})
  }

  files
}

export proc metadata_files_sha256(pkg: Package, files: List[Record]) [error] -> Result[Str] {
  var body = f"""name	${pkg.name}
ver	${pkg.ver}
deps	${pkg.deps.join(" ")}
mkdeps	${pkg.mkdeps.join(" ")}
"""

  if pkg.target_build_deps.len() > 0 {
    body = f"""${body}target_build_deps	${pkg.target_build_deps.join(" ")}
"""
  }

  for file in files {
    let path_text: Str = file.get("path")?
    let kind: Str = file.get("kind")?
    let mode: Int = file.get("mode")?
    let sha256: Str = file.get("sha256")?
    let target: Str = file.get("target")?

    body = f"""${body}${path_text}	${kind}	${mode}	${sha256}	${target}
"""
  }

  bytes.from_text(body).sha256().hex()
}

export proc write_package_metadata(path_value: Path, arch: Str, item: BuiltPackage) [fs, error] {
  fs.mkdir(path_value.parent)?
  let manifest = collect_manifest_text(item.manifest)?

  json.write(
    path_value,
    {
      arch,
      name: item.pkg.name,
      ver: item.pkg.ver,
      rel: item.pkg.rel,
      deps: item.pkg.deps,
      mkdeps: item.pkg.mkdeps,
      target_build_deps: item.pkg.target_build_deps,
      manifest,
      metadata_sha256: item.metadata_sha256,
      files: item.metadata_files,
    },
  )?
}

export proc load_installed_owners(root: Path) [fs, error] -> Result[Map[Str]] {
  var owners: Map[Str] = {}
  let packages_db = packages_db_path(root)

  if ! fs.exists(packages_db)? {
    return owners
  }

  let entries = fs.children(packages_db)?

  for entry in entries {
    if entry.kind == "dir" {
      let manifest = load_manifest(entry.path)?

      for rel_path in manifest {
        owners[rel_path.display()] = entry.name
      }
    }
  }

  owners
}

export proc ensure_installable(root: Path, pkg: Package, manifest: List[Path], installed_owners: Map[Str]) [fs, error] {
  for rel_path in manifest {
    let key = rel_path.display()

    if installed_owners.has(key) {
      let owner: Str = installed_owners.get(key)?

      if owner != pkg.name and ! pkg.replaces.contains(owner) {
        return Err(PmError.PackageConflict(f"${pkg.name} conflicts with ${owner}: ${key}"))
      }
    } else if fs.exists(fp"${root}/${rel_path}")? and ! is_etc_file(rel_path) {
      let root_str = root.display()
      var msg = f"${pkg.name} would overwrite unowned ${key} in root ${root_str}"

      if root_str.ends_with("/.world/root") or root_str.ends_with("/.world/build-root") {
        let cache_dir = root.parent.parent
        msg = f"${msg}\nstale world-plan cache: delete ${cache_dir.display()} to reset"
      }

      return Err(PmError.DirtyFilesystem(msg))
    }
  }
}

export proc install_etc_file(
  source_root: FsRoot,
  source: Path,
  dest_root: FsRoot,
  dest: Path,
  mode: Int,
  key: Str,
  old_sums: Map[Str],
  new_sums: Map[Str],
) [fs, error] {
  let new_sum: Str = new_sums.get(key)?
  var old_sum = ""

  if old_sums.has(key) {
    let value: Str = old_sums.get(key)?
    old_sum = value
  }

  var sys_sum = ""

  if fs.root_exists(dest_root, dest)? {
    sys_sum = fs.root_read(dest_root, dest)?.sha256().hex()
  }

  if old_sum == new_sum and new_sum != sys_sum {
    return
  }

  if sys_sum == "" or old_sum == sys_sum or sys_sum == new_sum {
    fs.root_install_file(source_root, source, dest_root, dest, mode, overwrite: true)?
    return
  }

  fs.root_install_file(source_root, source, dest_root, fp"${dest.parent}/${dest.name}.new", mode, overwrite: true)?
}

export proc install_manifest_entries(
  root: Path,
  stage: Path,
  pkg: Package,
  manifest: List[Path],
  old_sums: Map[Str],
  new_sums: Map[Str],
  installed_owners: Map[Str],
) [fs, error] {
  let source_root = fs.open_root(stage)?
  defer fs.close_root(source_root)
  let dest_root = fs.open_root(root)?
  defer fs.close_root(dest_root)

  for rel_path in manifest {
    let key = rel_path.display()
    var overwrite = false

    if installed_owners.has(key) {
      let owner: Str = installed_owners.get(key)?

      if owner == pkg.name or pkg.replaces.contains(owner) {
        overwrite = true
      }
    }

    match fs.root_readlink(source_root, rel_path) {
      Ok(target) => {
        fs.root_symlink(dest_root, target, rel_path, overwrite: overwrite)?
        continue
      }
      Err(_) => {}
    }

    let metadata = fs.root_metadata(source_root, rel_path)?

    if metadata.kind == "file" {
      let file_mode = metadata.mode % 4096

      if is_etc_file(rel_path) {
        install_etc_file(source_root, rel_path, dest_root, rel_path, file_mode, key, old_sums, new_sums)?
      } else {
        fs.root_install_file(source_root, rel_path, dest_root, rel_path, file_mode, overwrite: overwrite)?
      }
    }
  }
}

export proc dir_empty(path_value: Path) [fs, error] -> Result[Bool] {
  for _ in fs.ls(path_value)? {
    return false
  }

  true
}

export proc direct_extract_package(
  ctx: PmContext,
  pkg: Package,
  tarball: Path,
  manifest: List[Path],
  etcsums: List[EtcSum],
  installed_owners: Map[Str],
) [fs, error] {
  ensure_installable(ctx.root, pkg, manifest, installed_owners)?
  archive.tar_extract(tarball, ctx.root, 0, "auto", true)?
  write_package_db(ctx.root, pkg, manifest, etcsums)?
}

export proc collect_removable_manifest(
  root: Path,
  manifest: List[Path],
  etcsums: Map[Str],
) [fs, error] -> Result[List[Path]] {
  var removable: List[Path] = []
  let root_handle = fs.open_root(root)?
  defer fs.close_root(root_handle)

  for rel_path in manifest {
    let key = rel_path.display()

    if is_etc_file(rel_path) and etcsums.has(key) and fs.root_exists(root_handle, rel_path)? {
      let expected: Str = etcsums.get(key)?

      if fs.root_read(root_handle, rel_path)?.sha256().hex() == expected {
        removable = removable.push(rel_path)
      }
    } else {
      removable = removable.push(rel_path)
    }
  }

  removable
}

export proc write_package_db(root: Path, pkg: Package, manifest: List[Path], etcsums: List[EtcSum]) [fs, error] {
  let db = package_db_path(root, pkg.name)
  fs.mkdir(db)?
  let manifest_text = collect_manifest_text(manifest)?
  json.write(fp"${db}/manifest.json", manifest_text)?
  json.write(fp"${db}/etcsums.json", etcsums)?

  json.write(
    fp"${db}/metadata.json",
    {
      name: pkg.name,
      ver: pkg.ver,
      rel: pkg.rel,
      deps: pkg.deps,
      mkdeps: pkg.mkdeps,
      target_build_deps: pkg.target_build_deps,
      replaces: pkg.replaces,
      nostrip: pkg.nostrip,
      extract_install: pkg.extract_install,
      dir: pkg.dir.display(),
    },
  )?
}

export proc call_pkg_hook(pkg: Package, hook_name: Str, root: Path) [error] {
  let exports = pkg.exports

  if exports.has(hook_name) {
    let hook: Proc = exports.get(hook_name)?
    hook.call(root)?
  }
}

export proc call_installed_hook(metadata: Record, hook_name: Str, root: Path) [fs, error] {
  if ! metadata.has("dir") {
    return
  }

  let dir_text: Str = metadata.get("dir")?
  let pkgbuild = fp"${Path.parse(dir_text)?}/PKGBUILD.xsh"

  if ! fs.exists(pkgbuild)? {
    return
  }

  let exports = module.load(pkgbuild)?

  if exports.has(hook_name) {
    let hook: Proc = exports.get(hook_name)?
    hook.call(root)?
  }
}

export proc load_package_dirs(dirs: List[Path]) [fs, env, error] -> Result[List[Package]] {
  var packages: List[Package] = []
  var seen: Map[Bool] = {}

  for dir in dirs {
    let pkgbuild = fp"${dir}/PKGBUILD.xsh"
    let exports = module.load(pkgbuild)?
    let name: Str = exports.get("name")?
    let ver: Str = exports.get("ver")?
    let rel: Str = exports.get("rel")?
    let deps: List[Str] = exports.get("deps")?
    let mkdeps: List[Str] = exports.get("mkdeps")?
    var target_build_deps: List[Str] = []
    let sources: List[Path] = exports.get("sources")?
    let base_checksums: List[Str] = exports.get("checksums")?
    let checksums = select_checksums(exports, base_checksums)?
    var nostrip = false
    var extract_install = false
    var replaces: List[Str] = []

    if exports.has("target_build_deps") {
      target_build_deps = exports.get("target_build_deps")?
    }

    if exports.has("nostrip") {
      let value: Bool = exports.get("nostrip")?
      nostrip = value
    }

    if exports.has("extract_install") {
      let value: Bool = exports.get("extract_install")?
      extract_install = value
    }

    if exports.has("replaces") {
      replaces = exports.get("replaces")?
    }

    if name == "" {
      return Err(PmError.PackageContract(f"${dir.display()} exports an empty name"))
    }

    if ver == "" or rel == "" {
      return Err(PmError.PackageContract(f"${name} exports an empty version or release"))
    }

    if sources.len() != checksums.len() {
      return Err(PmError.PackageContract(f"${name} source/checksum count mismatch"))
    }

    if seen.has(name) {
      return Err(PmError.PackageContract(f"duplicate package ${name}"))
    }

    seen[name] = true

    packages = packages.push(
      {
        dir,
        exports,
        name,
        ver,
        rel,
        deps,
        mkdeps,
        target_build_deps,
        replaces,
        sources,
        checksums,
        nostrip,
        extract_install,
      },
    )
  }

  packages
}

export proc order_packages(
  root: Path,
  packages: List[Package],
  allow_installed_deps: Bool,
) [fs, error] -> Result[List[Package]] {
  var ordered: List[Package] = []
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
            if ! allow_installed_deps or ! fs.exists(package_db_path(root, dep))? {
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

export proc filter_packages_by_names(packages: List[Package], names: List[Str]) [error] -> Result[List[Package]] {
  var selected = [pkg for pkg in packages if names.contains(pkg.name)]
  selected
}

export proc collect_upgrade_names(root: Path, packages: List[Package]) [fs, error] -> Result[List[Str]] {
  var names: List[Str] = []

  for pkg in packages {
    let db = package_db_path(root, pkg.name)

    if fs.exists(db)? {
      let metadata = load_metadata(db)?
      let ver: Str = metadata.get("ver")?
      let rel: Str = metadata.get("rel")?

      if ver != pkg.ver or rel != pkg.rel {
        names = names.push(pkg.name)
      }
    }
  }

  if names.contains("pm") {
    return ["pm"]
  }

  names
}

export pure collect_local_index(packages: List[Package]) -> Result[List[PackageIndex]] {
  let index = [{
    name: pkg.name,
    ver: pkg.ver,
    rel: pkg.rel,
    deps: pkg.deps,
    mkdeps: pkg.mkdeps,
    target_build_deps: pkg.target_build_deps,
  } for pkg in packages]

  index
}

proc prepare_build_package_source(ctx: PmContext, pkg: Package) [fs, net, process, env, time, error] {
  let id = package_id(pkg.name, pkg.ver, pkg.rel)
  let pkg_work = fp"${ctx.work}/${id}"
  let src = fp"${pkg_work}/src"
  let reuse_work = (env.get("XSH_PM_REUSE_WORK") ?? "") == "1"
  let source_ready = fp"${pkg_work}/.source-ready"

  if ! reuse_work {
    fs.remove(pkg_work, missing_ok: true)?
  }

  if ! reuse_work or ! src.exists()? or ! source_ready.exists()? {
    fs.remove(src, missing_ok: true)?

    if pkg.sources.len() == 0 {
      fs.mkdir(src)?
    }

    prepare_package_source_tree(ctx.work, ctx.out, pkg, src, false, true, ! reuse_work)?

    fs.write(
      source_ready,
      """ok
""",
    )?
  }
}

proc chroot_build_enabled(ctx: PmContext) [env] -> Bool {
  if (env.get("XSH_PM_IN_CHROOT") ?? "") == "1" {
    return false
  }

  if (env.get("XSH_PM_BUILD_CHROOT") ?? "1") == "0" {
    return false
  }

  return ctx.command == "build-install" or ctx.command == "world-plan" or ctx.command == "build-set"
}

proc pm_source_root() [fs, env, error] -> Result[Path] {
  for candidate in [p"laputa", p"."] {
    if fs.exists(fp"${candidate}/pm.xsh")? and fs.exists(fp"${candidate}/pm")? {
      return path.absolute(candidate)?
    }
  }

  let module_path = env.get("XSH_MODULE_PATH") ?? "/usr/lib/pm"

  for entry in module_path.split(":") {
    let root = Path.parse(entry)?

    if fs.exists(fp"${root}/pm.xsh")? and fs.exists(fp"${root}/pm")? {
      return root
    }
  }

  return /usr/lib/pm
}

proc seed_chroot_runner(root: Path) [fs, process, env, error] {
  let xsh = xsh_runner()?
  fs.remove(fp"${root}/usr/local/bin/xsh-multicall", missing_ok: true)?

  for name in ["xsh", "xshi", "xsht"] {
    let dest = fp"${root}/usr/local/bin/${name}"
    fs.remove(dest, missing_ok: true)?
    fs.install(xsh_command_source(xsh, name)?, dest, 0o755, parents: true, overwrite: true)?
  }

  if fs.exists(/usr/lib/xsh)? {
    let _ = fs.copy_tree(/usr/lib/xsh, fp"${root}/usr/lib/xsh", parents: true, overwrite: true)?
  }

  let pm_root = pm_source_root()?
  fs.install(fp"${pm_root}/pm.xsh", fp"${root}/usr/lib/pm/pm.xsh", 0o644, parents: true, overwrite: true)?
  fs.remove(fp"${root}/usr/lib/pm/pm", missing_ok: true)?
  let _ = fs.copy_tree(fp"${pm_root}/pm", fp"${root}/usr/lib/pm/pm", parents: true, overwrite: true)?

  for sh in [fp"${root}/usr/bin/sh", fp"${root}/bin/sh"] {
    fs.mkdir(sh.parent)?
    fs.remove(sh, missing_ok: true)?

    fs.write(
      sh,
      """#!/usr/local/bin/xsh
run /usr/local/bin/xshi @args ?
""",
    )?

    fs.chmod(sh, 0o755)?
  }

  for tmp in [fp"${root}/tmp", fp"${root}/var/tmp"] {
    fs.mkdir(tmp)?
    fs.chmod(tmp, 0o1777)?
  }

  fs.mkdir(fp"${root}/proc")?

  for name in ["cpuinfo", "meminfo"] {
    let source = fp"/proc/${name}"
    let dest = fp"${root}/proc/${name}"

    if fs.exists(source)? {
      fs.copy(source, dest, overwrite: true)?
    } else if ! fs.exists(dest)? {
      fs.write(dest, "")?
    }
  }

  seed_chroot_device_paths(root)?
  fs.mkdir(fp"${root}/etc")?

  for name in ["resolv.conf", "hosts", "nsswitch.conf"] {
    let source = fp"/etc/${name}"

    if fs.exists(source)? {
      fs.copy(source, fp"${root}/etc/${name}", overwrite: true)?
    }
  }
}

export proc load_built_package_from_dest(
  pkg: Package,
  id: Str,
  tarball: Path,
  dest: Path,
) [fs, error] -> Result[BuiltPackage] {
  let db = package_db_path(dest, pkg.name)
  let manifest = load_manifest(db)?
  let etcsums: List[EtcSum] = json.read(fp"${db}/etcsums.json")?
  let metadata_files = collect_metadata_files(dest, manifest)?
  let metadata_sha256 = metadata_files_sha256(pkg, metadata_files)?

  return {
    pkg,
    id,
    tarball,
    manifest,
    etcsums,
    metadata_sha256,
    metadata_files,
  }
}

export proc build_prepared_package(pkg_dir: Path, src: Path, dest: Path, tarball: Path) [fs, process, env, error] {
  let packages = load_package_dirs([pkg_dir])?
  let pkg = packages[0]
  let makeflags = env.get("MAKEFLAGS") ?? f"-s -j${cpu.count()}"

  env {
    DESTDIR = dest
    LAPUTA_ROOT = "/"
    XSH_PM_NAME = pkg.name
    XSH_PM_VERSION = pkg.ver
    XSH_PM_RELEASE = pkg.rel
    XSH_PM_QUIET = "1"
    MAKEFLAGS = makeflags
    SHELL = "/usr/local/bin/xshi"
  } {
    let exports = pkg.exports

    if exports.has("prepare") {
      let prepare_fn: Proc = exports.get("prepare")?
      prepare_fn.call(src)?
    }

    fs.remove(dest, missing_ok: true)?
    fs.mkdir(dest)?

    if exports.has("build") {
      cd src {
        let build_fn: Proc = exports.get("build")?
        build_fn.call(dest)?
      } ?
    }
  } ?

  let manifest = fs.walk(dest)
    |> where .kind == "file" or .kind == "symlink"
    |> map { |entry|
      entry.path.strip_prefix(dest)?
    }
    |> sort-by .display()

  let etcsums = collect_etcsums(dest, manifest)?
  write_package_db(dest, pkg, manifest, etcsums)?
  let dest_text = dest.display()
  var archive_paths: List[Path] = []

  for entry in fs.walk(dest) {
    var include = entry.kind == "file" or entry.kind == "symlink"

    if pkg.extract_install and entry.kind == "dir" and entry.path.display() != dest_text and dir_empty(entry.path)? {
      include = true
    }

    if include {
      archive_paths = archive_paths.push(entry.path.strip_prefix(dest)?)
    }
  }

  archive_paths = archive_paths |> sort-by .display()
  fs.mkdir(tarball.parent)?
  archive.tar_create(tarball, dest, archive_paths, compression: "gz", overwrite: true)?
}

proc chroot_build_cache_dir(ctx: PmContext, pkg: Package) [] -> Path {
  return fp"${ctx.work}/.chroot-build-cache/${pkg.name}"
}

proc linux_kbuild_cache_files() [] -> List[Str] {
  return [
    ".xsh-kbuild-plan.json",
    ".xsh-kbuild-plan.fingerprint",
    ".xsh-kbuild-compile-flags.json",
    ".xsh-kbuild-archive-plan.json",
    ".xsh-kbuild-archive-plan.json.summary",
    ".xsh-kbuild-archive-plan.fingerprint",
  ]
}

proc seed_chroot_build_cache(ctx: PmContext, pkg: Package, src: Path) [fs, error] {
  if pkg.name != "linux" {
    return
  }

  let cache = chroot_build_cache_dir(ctx, pkg)

  for name in linux_kbuild_cache_files() {
    let cached = fp"${cache}/${name}"

    if cached.exists()? {
      fs.copy(cached, fp"${src}/${name}", overwrite: true)?
    }
  }
}

proc preserve_chroot_build_cache(ctx: PmContext, pkg: Package, src: Path) [fs, error] {
  if pkg.name != "linux" {
    return
  }

  let cache = chroot_build_cache_dir(ctx, pkg)
  fs.mkdir(cache)?

  for name in linux_kbuild_cache_files() {
    let source = fp"${src}/${name}"
    let cached = fp"${cache}/${name}"

    if source.exists()? {
      fs.copy(source, cached, overwrite: true)?
    } else {
      fs.remove(cached, missing_ok: true)?
    }
  }
}

proc build_packages_in_chroot(
  ctx: PmContext,
  packages: List[Package],
) [fs, net, process, env, time, error] -> Result[List[BuiltPackage]] {
  var built: List[BuiltPackage] = []
  var owners: Map[Str] = {}

  for pkg in packages {
    prepare_build_package_source(ctx, pkg)?
    seed_chroot_runner(ctx.root)?
    let id = package_id(pkg.name, pkg.ver, pkg.rel)
    let source_src = fp"${ctx.work}/${id}/src"
    let stage = fp"${ctx.root}/var/tmp/pm-build/${id}"
    let src = fp"${stage}/src"
    let pkg_dir = fp"${stage}/pkg"
    let dest = fp"${stage}/dest"
    let chroot_stage = fp"/var/tmp/pm-build/${id}"
    let chroot_pkg = fp"${chroot_stage}/pkg"
    let chroot_src = fp"${chroot_stage}/src"
    let chroot_dest = fp"${chroot_stage}/dest"
    let chroot_tarball = fp"${chroot_stage}/out/${id}.tar.gz"
    let host_tarball = fp"${stage}/out/${id}.tar.gz"
    let tarball = fp"${ctx.out}/${id}.tar.gz"
    let chroot_root = ctx.root
    let host_xsh = xsh_runner()?
    let host_chroot_runner = fp"${pm_source_root()?}/pm/chroot-run.xsh"
    let makeflags = env.get("MAKEFLAGS") ?? f"-s -j${cpu.count()}"
    let build_arch = util.build_arch()?
    let target_arch = util.target_arch()?
    fs.remove(stage, missing_ok: true)?
    fs.mkdir(stage)?
    fs.copy_tree(source_src, src, parents: true, overwrite: true)?
    fs.copy_tree(pkg.dir, pkg_dir, parents: true, overwrite: true)?
    seed_chroot_build_cache(ctx, pkg, src)?
    run_lifecycle_hooks("pre-build", pkg.name, ctx, src.display())?

    let chroot_argv = [
      host_xsh.display(),
      host_chroot_runner.display(),
      "--",
      chroot_root.display(),
      pkg.name,
      "/usr/local/bin/xsh",
      "/usr/lib/pm/pm.xsh",
      "--",
      "build-prepared-package",
      chroot_pkg.display(),
      chroot_src.display(),
      chroot_dest.display(),
      chroot_tarball.display(),
    ]

    env {
      LAPUTA_ROOT = "/"
      MAKEFLAGS = makeflags
      PATH = "/usr/local/bin:/usr/bin:/usr/lib/xsh/core:/bin"
      XSH_MODULE_PATH = "/usr/lib/pm"
      XSH_LINUX_REAL = "1"
      XSH_LINUX_KBUILD_DISCOVER_JOBS = env.get("XSH_LINUX_KBUILD_DISCOVER_JOBS") ?? ""
      XSH_LINUX_KBUILD_FORCE_ARCHIVES = env.get("XSH_LINUX_KBUILD_FORCE_ARCHIVES") ?? ""
      XSH_LINUX_KBUILD_JOBS = env.get("XSH_LINUX_KBUILD_JOBS") ?? ""
      XSH_LINUX_KBUILD_ONLY = env.get("XSH_LINUX_KBUILD_ONLY") ?? ""
      XSH_LINUX_KBUILD_PLAN = env.get("XSH_LINUX_KBUILD_PLAN") ?? ""
      XSH_LINUX_KBUILD_PROGRESS = env.get("XSH_LINUX_KBUILD_PROGRESS") ?? ""
      XSH_LINUX_KBUILD_PROGRESS_EVERY = env.get("XSH_LINUX_KBUILD_PROGRESS_EVERY") ?? "100"
      XSH_LINUX_KBUILD_REUSE_ARCHIVE_PLAN = env.get("XSH_LINUX_KBUILD_REUSE_ARCHIVE_PLAN") ?? ""
      XSH_LINUX_KBUILD_REUSE_ARCHIVES = env.get("XSH_LINUX_KBUILD_REUSE_ARCHIVES") ?? ""
      XSH_LINUX_KBUILD_STOP_AFTER = env.get("XSH_LINUX_KBUILD_STOP_AFTER") ?? ""
      XSH_LINUX_KBUILD_TRUST_PLAN_CACHE = env.get("XSH_LINUX_KBUILD_TRUST_PLAN_CACHE") ?? ""
      XSH_LINUX_KBUILD_USE_PLAN = env.get("XSH_LINUX_KBUILD_USE_PLAN") ?? ""
      XSH_LINUX_KBUILD_USE_PLAN_TEXT = env.get("XSH_LINUX_KBUILD_USE_PLAN_TEXT") ?? ""
      XSH_MAKE_PROGRESS = env.get("XSH_MAKE_PROGRESS") ?? ""
      XSH_PM_ARCH = target_arch
      XSH_PM_BUILD_ARCH = build_arch
      XSH_PM_BUILD_ROOT = "/"
      XSH_PM_TARGET_ARCH = target_arch
      XSH_PM_IN_CHROOT = "1"
      SHELL = "/usr/local/bin/xshi"
    } {
      let status = process.run(process.command_argv(host_xsh, chroot_argv))?
      preserve_chroot_build_cache(ctx, pkg, src)?

      if ! status.ok {
        if status.exited() {
          abort(status.exit_code()?)
        }

        return Err(PmError.ExtensionFailed(f"chroot build for ${pkg.name} was signaled"))
      }
    } ?

    fs.install(host_tarball, tarball, 0o644, parents: true, overwrite: true)?
    let item = load_built_package_from_dest(pkg, id, tarball, dest)?

    for rel_path in item.manifest {
      let key = rel_path.display()

      if owners.has(key) {
        let owner: Str = owners.get(key)?
        return Err(PmError.PackageConflict(f"${pkg.name} conflicts with ${owner}: ${key}"))
      }

      owners[key] = pkg.name
    }

    run_package_proof(ctx, pkg, id, tarball, item.manifest, built)?
    run_lifecycle_hooks("post-build", pkg.name, ctx, tarball.display())?
    built = built.push(item)
    print ${pkg.name} ${id} item.manifest.len() "built"
  }

  built
}

export proc build_packages(
  ctx: PmContext,
  packages: List[Package],
) [fs, net, process, env, time, error] -> Result[List[BuiltPackage]] {
  if chroot_build_enabled(ctx) {
    return build_packages_in_chroot(ctx, packages)
  }

  var built: List[BuiltPackage] = []
  var owners: Map[Str] = {}

  if packages.len() > 0 {
    let _ = packages
      |> par-map --jobs=packages.len() { |pkg|
        prepare_build_package_source(ctx, pkg)?
        pkg.name
      }
  }

  for pkg in packages {
    let id = package_id(pkg.name, pkg.ver, pkg.rel)
    let pkg_work = fp"${ctx.work}/${id}"
    let src = fp"${pkg_work}/src"
    let dest = fp"${pkg_work}/dest"
    let tarball = fp"${ctx.out}/${id}.tar.gz"
    run_lifecycle_hooks("pre-build", pkg.name, ctx, src.display())?
    let makeflags = env.get("MAKEFLAGS") ?? f"-s -j${cpu.count()}"

    env {
      DESTDIR = dest
      XSH_PM_NAME = pkg.name
      XSH_PM_VERSION = pkg.ver
      XSH_PM_RELEASE = pkg.rel
      XSH_PM_QUIET = "1"
      MAKEFLAGS = makeflags
    } {
      let exports = pkg.exports

      if exports.has("prepare") {
        let prepare_fn: Proc = exports.get("prepare")?
        prepare_fn.call(src)?
      }

      fs.remove(dest, missing_ok: true)?
      fs.mkdir(dest)?

      if exports.has("build") {
        cd src {
          let build_fn: Proc = exports.get("build")?
          build_fn.call(dest)?
        } ?
      }
    } ?

    let manifest = fs.walk(dest)
      |> where .kind == "file" or .kind == "symlink"
      |> map { |entry|
        entry.path.strip_prefix(dest)?
      }
      |> sort-by .display()

    for rel_path in manifest {
      let key = rel_path.display()

      if owners.has(key) {
        let owner: Str = owners.get(key)?
        return Err(PmError.PackageConflict(f"${pkg.name} conflicts with ${owner}: ${key}"))
      }

      owners[key] = pkg.name
    }

    let etcsums = collect_etcsums(dest, manifest)?
    write_package_db(dest, pkg, manifest, etcsums)?
    let dest_text = dest.display()
    var archive_paths: List[Path] = []

    for entry in fs.walk(dest) {
      var include = entry.kind == "file" or entry.kind == "symlink"

      if pkg.extract_install and entry.kind == "dir" and entry.path.display() != dest_text and dir_empty(entry.path)? {
        include = true
      }

      if include {
        archive_paths = archive_paths.push(entry.path.strip_prefix(dest)?)
      }
    }

    archive_paths = archive_paths |> sort-by .display()
    fs.mkdir(ctx.out)?
    archive.tar_create(tarball, dest, archive_paths, compression: "gz", overwrite: true)?
    run_package_proof(ctx, pkg, id, tarball, manifest, built)?
    run_lifecycle_hooks("post-build", pkg.name, ctx, tarball.display())?
    let metadata_files = collect_metadata_files(dest, manifest)?
    let metadata_sha256 = metadata_files_sha256(pkg, metadata_files)?

    built = built.push(
      {
        pkg,
        id,
        tarball,
        manifest,
        etcsums,
        metadata_sha256,
        metadata_files,
      },
    )

    print ${pkg.name} ${id} manifest.len() "built"
  }

  built
}

proc xsh_runner() [fs, process, env, error] -> Result[Path] {
  let host = (env.get("XSH_HOST") ?? "").trim()

  if host != "" {
    let host_path = Path.parse(host)?

    if fs.exists(host_path)? {
      return host_path
    }
  }

  if fs.exists(/usr/local/bin/xsh)? {
    return /usr/local/bin/xsh
  }

  process.which("xsh")?
}

proc regular_xsh_source(xsh: Path) [fs, error] -> Result[Path] {
  let metadata = fs.metadata(xsh)?

  if metadata.kind != "symlink" {
    return xsh
  }

  let target = xsh.readlink()?

  if target.display().starts_with("/") {
    return target
  }

  fp"${xsh.parent}/${target}"
}

proc xsh_command_source(xsh: Path, name: Str) [fs, process, error] -> Result[Path] {
  let sibling = fp"${xsh.parent}/${name}"

  if fs.exists(sibling)? {
    return regular_xsh_source(sibling)?
  }

  var source = regular_xsh_source(xsh)?

  match process.which(name) {
    Ok(found) => source = regular_xsh_source(found)?
    Err(_) => {}
  }

  source
}

proc seed_package_proof_shell(proof_root: Path, xsh: Path) [fs, process, env, error] {
  fs.remove(fp"${proof_root}/usr/local/bin/xsh-multicall", missing_ok: true)?

  for name in ["xsh", "xshi", "xsht"] {
    let dest = fp"${proof_root}/usr/local/bin/${name}"
    fs.remove(dest, missing_ok: true)?
    fs.install(xsh_command_source(xsh, name)?, dest, 0o755, parents: true, overwrite: true)?
  }

  for proof_sh in [fp"${proof_root}/usr/bin/sh", fp"${proof_root}/bin/sh"] {
    fs.mkdir(proof_sh.parent)?
    fs.remove(proof_sh, missing_ok: true)?

    fs.write(
      proof_sh,
      """#!/usr/local/bin/xsh
run /usr/local/bin/xshi @args ?
""",
    )?

    fs.chmod(proof_sh, 0o755)?
  }

  let pm_root = pm_source_root()?
  fs.install(fp"${pm_root}/pm.xsh", fp"${proof_root}/usr/lib/pm/pm.xsh", 0o644, parents: true, overwrite: true)?
  fs.remove(fp"${proof_root}/usr/lib/pm/pm", missing_ok: true)?
  let _ = fs.copy_tree(fp"${pm_root}/pm", fp"${proof_root}/usr/lib/pm/pm", parents: true, overwrite: true)?
}

proc seed_chroot_device_paths(root: Path) [fs, error] {
  fs.mkdir(fp"${root}/dev")?
  let dev_null = fp"${root}/dev/null"

  if ! fs.exists(dev_null)? {
    fs.write(dev_null, "")?
    fs.chmod(dev_null, 0o666)?
  }

  let dev_fd = fp"${root}/dev/fd"
  fs.remove(dev_fd, missing_ok: true)?
  fs.symlink(/proc/self/fd, dev_fd)?
}

proc mount_package_proof_devpts(proof_root: Path) [fs, process, error] -> Result[Path] {
  let dev = fp"${proof_root}/dev"
  let pts = fp"${dev}/pts"
  fs.mkdir(pts)?
  fs.remove(fp"${dev}/ptmx", missing_ok: true)?
  fs.symlink(p"pts/ptmx", fp"${dev}/ptmx")?
  let mount = process.which("mount")?
  run $mount "-t" "devpts" "devpts" $pts "-o" "newinstance,ptmxmode=0666,mode=0620" ?
  pts
}

proc unmount_package_proof_devpts(pts: Path) [process] {
  match process.which("umount") {
    Ok(umount) => let _ = run.status $umount $pts
    Err(_) => {}
  }
}

proc verify_package_proof_root(root: Path, name: Str) [fs, error] {
  let db = package_db_path(root, name)

  if ! fs.exists(db)? {
    return Err(PmError.PackageTarball(f"${name} proof root is missing package metadata"))
  }

  let manifest = load_manifest(db)?

  for rel_path in manifest {
    let installed = fp"${root}/${rel_path}"

    match fs.metadata(installed) {
      Ok(_) => {}
      Err(_) => return Err(PmError.PackageTarball(f"${name} proof root is missing ${rel_path.display()}"))
    }
  }
}

pure manifest_installs_service(manifest: List[Path]) -> Bool {
  for rel_path in manifest {
    let entry = rel_path.display()

    if entry.starts_with("usr/lib/xinit/services/") and entry.ends_with(".xsh") {
      return true
    }
  }

  return false
}

# Locate an xinit script to validate service definitions with. Prefers an
# explicit XINIT_HOST override, then an installed /usr/bin/xinit, then PATH.
# Errors with an actionable PackageContract when none is found, since a package
# that ships service.xsh cannot be proven without one.
proc resolve_service_xinit(name: Str) [fs, process, env, error] -> Result[Path] {
  let host = (env.get("XINIT_HOST") ?? "").trim()

  if host != "" {
    let host_path = Path.parse(host)?

    if fs.exists(host_path)? {
      return host_path
    }
  }

  if fs.exists(/usr/bin/xinit)? {
    return /usr/bin/xinit
  }

  match process.which("xinit") {
    Ok(found) => return found
    Err(_) => {}
  }

  return Err(
    PmError.PackageContract(
      f"${name} ships service.xsh but no xinit was found to validate it; install the xinit package or set XINIT_HOST to an xinit script",
    ),
  )
}

# A package is an xinit service when it ships a service.xsh next to its
# PKGBUILD, mirroring the required proof.xsh. The service definition must be
# installed under /usr/lib/xinit/services/ and is validated with `xinit check`
# during the package proof, so a malformed or undeclared service fails the
# build instead of the running system.
proc verify_service_contract(pkg: Package, manifest: List[Path]) [fs, process, env, error] {
  let service_file = fp"${pkg.dir}/service.xsh"
  let has_service = fs.exists(service_file)?
  let installs_service = manifest_installs_service(manifest)

  if installs_service and ! has_service {
    return Err(
      PmError.PackageContract(
        f"${pkg.name} installs an xinit service under /usr/lib/xinit/services/ but is missing service.xsh",
      ),
    )
  }

  if has_service and ! installs_service {
    return Err(
      PmError.PackageContract(
        f"${pkg.name} defines service.xsh but build() does not install it under /usr/lib/xinit/services/",
      ),
    )
  }

  if ! has_service {
    return
  }

  let xinit = resolve_service_xinit(pkg.name)?
  let xsh = xsh_runner()?
  let scratch_root = fs.tempdir()?
  defer fs.close_root(scratch_root)?
  let scratch = fs.root_path(scratch_root)?
  let out_log = fp"${scratch}/service-check.out"
  let err_log = fp"${scratch}/service-check.err"
  let status = run.status $xsh $xinit "--" check $service_file > $out_log 2> $err_log

  if ! status.ok {
    return Err(
      PmError.PackageContract(
        f"${pkg.name} service.xsh failed xinit check: ${err_log.read_text()?.trim()} ${out_log.read_text()?.trim()}",
      ),
    )
  }

  print f"${pkg.name} service ${out_log.read_text()?.trim()}"
}

proc run_package_proof(
  ctx: PmContext,
  pkg: Package,
  id: Str,
  tarball: Path,
  manifest: List[Path],
  previous: List[BuiltPackage],
) [fs, process, env, error] {
  let proof = fp"${pkg.dir}/proof.xsh"

  if ! fs.exists(proof)? {
    return Err(PmError.PackageContract(f"${pkg.name} is missing proof.xsh"))
  }

  verify_service_contract(pkg, manifest)?
  let proof_root = fp"${ctx.work}/${id}-proof-root"
  fs.remove(proof_root, missing_ok: true)?
  fs.mkdir(proof_root)?

  if fs.exists(ctx.root)? {
    fs.copy_tree(ctx.root, proof_root, parents: true, overwrite: true)?
  }

  for item in previous {
    archive.tar_extract(item.tarball, proof_root, 0, "auto", true)?
  }

  let proof_db = package_db_path(proof_root, pkg.name)

  if fs.exists(proof_db)? {
    let old_manifest = load_manifest(proof_db)?
    let _ = fs.remove_manifest(proof_root, old_manifest, missing_ok: true)?
    fs.remove(proof_db, missing_ok: true)?
  }

  let installed_owners = load_installed_owners(proof_root)?

  for rel_path in manifest {
    let key = rel_path.display()

    if ! installed_owners.has(key) {
      fs.remove(fp"${proof_root}/${rel_path}", missing_ok: true)?
    } else {
      let owner: Str = installed_owners.get(key)?

      if pkg.replaces.contains(owner) {
        fs.remove(fp"${proof_root}/${rel_path}", missing_ok: true)?
      }
    }
  }

  archive.tar_extract(tarball, proof_root, 0, "auto", true)?
  verify_package_proof_root(proof_root, pkg.name)?
  let xsh = xsh_runner()?
  seed_package_proof_shell(proof_root, xsh)?
  seed_chroot_device_paths(proof_root)?
  let build_arch = util.build_arch()?
  let target_arch = util.target_arch()?
  let native_proof = build_arch == target_arch

  if native_proof {
    # note: not working on macos
    # let proof_devpts = mount_package_proof_devpts(proof_root)?
    # defer unmount_package_proof_devpts(proof_devpts)
    let proof_stage = fp"${proof_root}/var/tmp/pm-proof/${pkg.name}"
    fs.mkdir(proof_stage)?
    fs.install(proof, fp"${proof_stage}/proof.xsh", 0o644, parents: true, overwrite: true)?
    let host_chroot_runner = fp"${pm_source_root()?}/pm/chroot-run.xsh"

    env {
      LAPUTA_ROOT = "/"
      PATH = "/usr/local/bin:/usr/bin:/usr/lib/xsh/core:/bin"
      XSH_MODULE_PATH = "/usr/lib/pm"
      XSH_LINUX_REAL = "1"
      XSH_PM_ARCH = target_arch
      XSH_PM_BUILD_ARCH = build_arch
      XSH_PM_BUILD_ROOT = "/"
      XSH_PM_PROOF_ROOT = "/"
      XSH_PM_PROOF_HOST_PATH = env.get("PATH") ?? ""
      XSH_PM_TARGET_ARCH = target_arch
      SHELL = "/usr/local/bin/xshi"
    } {
      run $xsh $host_chroot_runner "--" $proof_root $pkg.name "/usr/local/bin/xsh" fp"/var/tmp/pm-proof/${pkg.name}/proof.xsh" "--" "/" ?
    } ?
  } else {
    env {
      PATH = f"${proof_root}/usr/local/bin:${proof_root}/usr/bin:${env.get("PATH") ?? ""}"
      XSH_MODULE_PATH = env.get("XSH_MODULE_PATH") ?? "/usr/lib/pm"
      XSH_PM_PROOF_ROOT = proof_root.display()
      XSH_PM_PROOF_HOST_PATH = env.get("PATH") ?? ""
      SHELL = fp"${proof_root}/usr/local/bin/xshi".display()
    } {
      run $xsh $proof "--" $proof_root ?
    } ?
  }

  print ${pkg.name} "proof" "ok"
}

export proc install_built_packages(ctx: PmContext, built: List[BuiltPackage]) [fs, process, env, error] {
  for item in built {
    let install_stage = fp"${ctx.work}/${item.id}-install"
    fs.remove(install_stage, missing_ok: true)?
    fs.mkdir(install_stage)?
    archive.tar_extract(item.tarball, install_stage, 0, "auto", true)?
    let db = package_db_path(ctx.root, item.pkg.name)
    let old_manifest = load_manifest(db)?
    let old_sums = load_etcsums(db)?
    let new_sums = map_etcsums(item.etcsums)?
    let installed_owners = load_installed_owners(ctx.root)?

    if item.pkg.extract_install and ! fs.exists(db)? {
      run_lifecycle_hooks("pre-install", item.pkg.name, ctx, "local")?
      call_pkg_hook(item.pkg, "pre_install", ctx.root)?
      direct_extract_package(ctx, item.pkg, item.tarball, item.manifest, item.etcsums, installed_owners)?
      call_pkg_hook(item.pkg, "post_install", ctx.root)?
      run_lifecycle_hooks("post-install", item.pkg.name, ctx, "local")?
      print ${item.pkg.name} item.manifest.len() archive.tar_list(item.tarball)?.len() installed
      continue
    }

    ensure_installable(ctx.root, item.pkg, item.manifest, installed_owners)?
    run_lifecycle_hooks("pre-install", item.pkg.name, ctx, "local")?
    call_pkg_hook(item.pkg, "pre_install", ctx.root)?
    let old_manifest_extra = collect_old_manifest_extra(old_manifest, item.manifest)?
    let _ = fs.remove_manifest(ctx.root, old_manifest_extra, missing_ok: true)?
    install_manifest_entries(ctx.root, install_stage, item.pkg, item.manifest, old_sums, new_sums, installed_owners)?
    write_package_db(ctx.root, item.pkg, item.manifest, item.etcsums)?
    call_pkg_hook(item.pkg, "post_install", ctx.root)?
    run_lifecycle_hooks("post-install", item.pkg.name, ctx, "local")?
    print ${item.pkg.name} item.manifest.len() archive.tar_list(item.tarball)?.len() installed
  }
}

export proc collect_installed_names(root: Path) [fs, error] -> Result[List[Str]] {
  var names: List[Str] = []
  let packages_db = packages_db_path(root)

  if ! fs.exists(packages_db)? {
    return names
  }

  let entries = fs.children(packages_db)
    |> where .kind == "dir"
    |> sort-by .name

  for entry in entries {
    names = names.push(entry.name)
  }

  names
}

export proc ensure_no_dependents(root: Path, names: List[Str]) [fs, error] {
  let installed_names = collect_installed_names(root)?

  for installed in installed_names {
    if ! names.contains(installed) {
      let metadata = load_metadata(package_db_path(root, installed))?
      let deps: List[Str] = metadata.get("deps")?

      for target in names {
        if deps.contains(target) {
          return Err(PmError.DependentPackage(f"${installed} depends on ${target}"))
        }
      }
    }
  }
}

export proc remove_installed_package(ctx: PmContext, name: Str) [fs, process, env, error] {
  let db = package_db_path(ctx.root, name)

  if ! fs.exists(db)? {
    return Err(PmError.PackageNotInstalled(f"${name} is not installed"))
  }

  let metadata = load_metadata(db)?
  run_lifecycle_hooks("pre-remove", name, ctx, "")?
  call_installed_hook(metadata, "pre_remove", ctx.root)?
  let manifest = load_manifest(db)?
  let etcsums = load_etcsums(db)?
  let removable = collect_removable_manifest(ctx.root, manifest, etcsums)?
  let removed = fs.remove_manifest(ctx.root, removable, missing_ok: true)?
  fs.remove(db, missing_ok: true)?
  call_installed_hook(metadata, "post_remove", ctx.root)?
  run_lifecycle_hooks("post-remove", name, ctx, "")?
  print ${name} ${removed.removed} "removed"
}

export proc remove_installed_packages(ctx: PmContext, names: List[Str]) [fs, process, env, error] {
  ensure_no_dependents(ctx.root, names)?

  for name in names {
    remove_installed_package(ctx, name)?
  }
}

export proc remove_built_packages(ctx: PmContext, built: List[BuiltPackage]) [fs, process, env, error] {
  for item in built {
    remove_installed_package(ctx, item.pkg.name)?
  }
}

export proc print_installed_list(root: Path) [fs, error] {
  let installed_names = collect_installed_names(root)?

  for name in installed_names {
    let metadata = load_metadata(package_db_path(root, name))?
    let ver: Str = metadata.get("ver")?
    let rel: Str = metadata.get("rel")?
    print ${name} version_id(ver, rel)
  }
}

export proc print_package_info(root: Path, name: Str) [fs, error] {
  let db = package_db_path(root, name)

  if ! fs.exists(db)? {
    return Err(PmError.PackageNotInstalled(f"${name} is not installed"))
  }

  let metadata = load_metadata(db)?
  let ver: Str = metadata.get("ver")?
  let rel: Str = metadata.get("rel")?
  let deps: List[Str] = metadata.get("deps")?
  let mkdeps: List[Str] = metadata.get("mkdeps")?
  let empty_target_build_deps: List[Str] = []

  let target_build_deps: List[Str] = if metadata.has("target_build_deps") {
    metadata.get("target_build_deps")?
  } else {
    empty_target_build_deps
  }

  let manifest = load_manifest(db)?
  print ${name} version_id(ver, rel)
  print "deps" deps.join(" ")
  print "mkdeps" mkdeps.join(" ")
  print "target_build_deps" target_build_deps.join(" ")
  print "files" manifest.len()
}

proc installed_package_deps(root: Path, name: Str) [fs, error] -> Result[List[Str]] {
  let db = package_db_path(root, name)

  if ! fs.exists(db)? {
    return Err(PmError.MissingDependency(f"${name} is not installed"))
  }

  let metadata = load_metadata(db)?
  metadata.get("deps")?
}

export pure tree_branch(last: Bool) -> Str {
  if last {
    return "`-- "
  }

  return "|-- "
}

export pure tree_child_prefix(prefix: Str, last: Bool) -> Str {
  if last {
    return f"${prefix}    "
  }

  return f"${prefix}|   "
}

proc print_dependency_tree_node(
  root: Path,
  name: Str,
  prefix: Str,
  last: Bool,
  root_node: Bool,
  expanded: Map[Bool],
) [fs, error] -> Result[Map[Bool]] {
  let repeated = expanded.get(name, false)
  var label = name

  if repeated {
    label = f"${name} (*)"
  }

  if root_node {
    print $label
  } else {
    print ${prefix}${tree_branch(last)}${label}
  }

  if repeated {
    return expanded
  }

  var next_expanded = expanded.set(name, true)
  let deps = installed_package_deps(root, name)?
  var dep_index = 0
  var child_prefix = ""

  if ! root_node {
    child_prefix = tree_child_prefix(prefix, last)
  }

  while dep_index < deps.len() {
    let dep = deps[dep_index]

    next_expanded = print_dependency_tree_node(
      root,
      dep,
      child_prefix,
      dep_index == deps.len() - 1,
      false,
      next_expanded,
    )?

    dep_index += 1
  }

  next_expanded
}

export proc collect_installed_tree_roots(root: Path) [fs, error] -> Result[List[Str]] {
  let installed_names = collect_installed_names(root)?
  var depended: Map[Bool] = {}

  for name in installed_names {
    let deps = installed_package_deps(root, name)?

    for dep in deps {
      if installed_names.contains(dep) {
        depended[dep] = true
      } else {
        return Err(PmError.MissingDependency(f"${name} depends on missing ${dep}"))
      }
    }
  }

  var roots = [name for name in installed_names if ! depended.get(name, false)]
  roots
}

export proc print_dependency_tree(root: Path, names: List[Str]) [fs, error] {
  var roots = names

  if roots.len() == 0 {
    roots = collect_installed_tree_roots(root)?
  }

  var expanded: Map[Bool] = {}

  for name in roots {
    expanded = print_dependency_tree_node(root, name, "", true, true, expanded)?
  }
}

export proc print_outdated(root: Path, packages: List[Package]) [fs, error] {
  for pkg in packages {
    let db = package_db_path(root, pkg.name)

    if fs.exists(db)? {
      let metadata = load_metadata(db)?
      let ver: Str = metadata.get("ver")?
      let rel: Str = metadata.get("rel")?

      if ver != pkg.ver or rel != pkg.rel {
        print ${pkg.name} version_id(ver, rel) "->" version_id(pkg.ver, pkg.rel)
      }
    }
  }
}

export proc print_search_matches(root: Path, query: Str, packages: List[Package]) [fs, error] {
  for pkg in packages {
    if query in pkg.name {
      print ${pkg.name} version_id(pkg.ver, pkg.rel) "local"
    }
  }

  let installed_names = collect_installed_names(root)?

  for name in installed_names {
    if query in name {
      let metadata = load_metadata(package_db_path(root, name))?
      let ver: Str = metadata.get("ver")?
      let rel: Str = metadata.get("rel")?
      print ${name} version_id(ver, rel) "installed"
    }
  }
}

export proc write_local_index(out: Path, packages: List[Package]) [fs, error] {
  fs.mkdir(out)?
  let index = collect_local_index(packages)?
  json.write(fp"${out}/index.json", index)?

  for pkg in packages {
    print ${pkg.name} version_id(pkg.ver, pkg.rel) "indexed"
  }
}

export proc print_package_checksums(work: Path, pkg: Package) [fs, net, process, env, time, error] {
  let arch = machine_arch()?
  let generated = generate_checksums_for(work, pkg, arch, pkg.checksums)?

  for checksum in generated {
    print ${pkg.name} $checksum
  }
}

export proc update_package_checksums(work: Path, pkg: Package) [fs, net, process, env, time, error] {
  let updates = collect_checksum_updates(work, pkg)?

  for update in updates {
    write_checksum_field(pkg, update.field, update.values)?
    print ${pkg.name} ${update.field} updated
  }
}

export proc download_package_sources(work: Path, out: Path, pkg: Package) [fs, net, process, env, time, error] {
  let id = package_id(pkg.name, pkg.ver, pkg.rel)
  let src = fp"${work}/download/${id}"
  fs.remove(src, missing_ok: true)?
  fs.mkdir(src)?
  prepare_package_source_tree(work, out, pkg, src, false, true, true)?
  print ${pkg.name} "sources" "downloaded"
}
