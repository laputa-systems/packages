use extensions
use local
use remote
use types
use util

export proc install_remote_metapackage(ctx: PmContext, pkg: RemotePackage) [fs, process, env, error] {
  let local_pkg = package_from_remote(pkg)?
  print --flush ${pkg.name} version_id(pkg.ver, pkg.rel) "install:" "starting"
  run_lifecycle_hooks("pre-install", pkg.name, ctx, "remote-metapackage")?
  write_package_db(ctx.root, local_pkg, [], [])?
  run_lifecycle_hooks("post-install", pkg.name, ctx, "remote-metapackage")?
  print ${pkg.name} version_id(pkg.ver, pkg.rel) "registered"
}

proc metadata_manifest_paths(metadata: Record) [error] -> Result[List[Path]] {
  let manifest_text: List[Str] = metadata.get("manifest")?
  var manifest = [fp"${rel_text}" for rel_text in manifest_text]
  manifest
}

proc metadata_etcsums(metadata: Record) [error] -> Result[List[EtcSum]] {
  let files: List[Record] = metadata.get("files")?
  var sums: List[EtcSum] = []

  for file in files {
    let path_text: Str = file.get("path")?
    let kind: Str = file.get("kind")?
    let sha256: Str = file.get("sha256")?

    if kind == "file" and is_etc_file(fp"${path_text}") {
      sums = sums.push({path: path_text, sha256})
    }
  }

  sums
}

proc load_remote_metadata_sidecar(path_value: Path, pkg: RemotePackage) [fs, error] -> Result[Record] {
  let metadata: Record = json.read(path_value)?
  let arch: Str = metadata.get("arch")?
  let name: Str = metadata.get("name")?
  let ver: Str = metadata.get("ver")?
  let rel: Str = metadata.get("rel")?

  if arch != pkg.arch or name != pkg.name or ver != pkg.ver or rel != pkg.rel {
    return Err(
      PmError.PackageContract(f"${path_value.display()} does not match ${pkg.name} ${version_id(pkg.ver, pkg.rel)}"),
    )
  }

  metadata
}

export proc install_remote_tarball(
  ctx: PmContext,
  pkg: RemotePackage,
  tarball: Path,
  from_cache: Bool,
) [fs, net, process, env, time, error] {
  let id = package_id(pkg.name, pkg.ver, pkg.rel)
  let install_stage = fp"${ctx.work}/${id}-remote-install"
  let label = if from_cache { "cache-installed" } else { "remote-installed" }
  print --flush ${pkg.name} version_id(pkg.ver, pkg.rel) "install:" "starting" $label
  let db = package_db_path(ctx.root, pkg.name)
  var manifest: List[Path] = []
  var etcsums: List[EtcSum] = []
  var local_pkg = package_from_remote(pkg)?
  let sidecar = fetch_remote_metadata_sidecar(ctx.out, pkg)?
  var have_sidecar = false

  if sidecar.found {
    let metadata = load_remote_metadata_sidecar(sidecar.path, pkg)?
    manifest = metadata_manifest_paths(metadata)?
    etcsums = metadata_etcsums(metadata)?
    have_sidecar = true
  } else {
    fs.remove(install_stage, missing_ok: true)?
    fs.mkdir(install_stage)?
    archive.tar_extract(tarball, install_stage, 0, "auto", true)?
    let stage_db = package_db_path(install_stage, pkg.name)
    manifest = load_manifest(stage_db)?
    etcsums = json.read(fp"${stage_db}/etcsums.json")?
    local_pkg = package_with_extract_install(local_pkg, load_extract_install(stage_db)?)
  }

  let old_manifest = load_manifest(db)?
  let old_sums = load_etcsums(db)?
  let new_sums = map_etcsums(etcsums)?
  let installed_owners = load_installed_owners(ctx.root)?

  if have_sidecar and ! fs.exists(db)? {
    run_lifecycle_hooks("pre-install", pkg.name, ctx, "remote-tarball")?
    direct_extract_package(ctx, local_pkg, tarball, manifest, etcsums, installed_owners)?
    run_lifecycle_hooks("post-install", pkg.name, ctx, "remote-tarball")?
    print ${pkg.name} manifest.len() $label
    return
  }

  if local_pkg.extract_install and ! fs.exists(db)? {
    run_lifecycle_hooks("pre-install", pkg.name, ctx, "remote-tarball")?
    direct_extract_package(ctx, local_pkg, tarball, manifest, etcsums, installed_owners)?
    run_lifecycle_hooks("post-install", pkg.name, ctx, "remote-tarball")?
    print ${pkg.name} manifest.len() $label
    return
  }

  if have_sidecar {
    fs.remove(install_stage, missing_ok: true)?
    fs.mkdir(install_stage)?
    archive.tar_extract(tarball, install_stage, 0, "auto", true)?
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
  print ${pkg.name} manifest.len() $label
}

export proc install_remote_packages(ctx: PmContext, names: List[Str]) [fs, net, process, env, time, error] {
  let index = ensure_remote_index(ctx.out)?
  let selected = collect_remote_packages(ctx.root, index, names)?
  let ordered = order_remote_packages(ctx.root, selected)?
  let tarball_packages = ordered |> where ! .metapackage
  var tarballs: Map[Path] = {}
  var tarball_from_cache: Map[Bool] = {}

  if tarball_packages.len() > 0 {
    let downloaded = tarball_packages
      |> par-map --jobs=tarball_packages.len() { |pkg|
        let result = download_remote_tarball(ctx.out, pkg)?
        {name: pkg.name, tarball: result.tarball, from_cache: result.from_cache}
      }

    for item in downloaded {
      tarballs[item.name] = item.tarball
      tarball_from_cache[item.name] = item.from_cache
    }
  }

  for pkg in ordered {
    if pkg.metapackage {
      install_remote_metapackage(ctx, pkg)?
    } else {
      let tarball: Path = tarballs.get(pkg.name)?
      let from_cache: Bool = tarball_from_cache.get(pkg.name, false)
      install_remote_tarball(ctx, pkg, tarball, from_cache)?
    }
  }
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
