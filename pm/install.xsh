##! PM install operations and shared package-manager policy.
use extensions
use local
use remote
use types
use util

## Exported PM declaration `install_remote_metapackage`.
export proc install_remote_metapackage(ctx: types.PmContext, pkg: types.RemotePackage) [fs, process, env, time, error] {
  let started = time.now()
  let local_pkg = remote.package_from_remote(pkg)?
  print --flush ${pkg.name} util.version_id(pkg.ver, pkg.rel) "install:" "starting"
  extensions.run_lifecycle_hooks("pre-install", pkg.name, ctx, "remote-metapackage")?
  local.write_package_db(ctx.root, local_pkg, [], [])?
  extensions.run_lifecycle_hooks("post-install", pkg.name, ctx, "remote-metapackage")?
  print ${pkg.name} util.version_id(pkg.ver, pkg.rel) "registered"
  let elapsed = time.now() - started
  print --flush "pm-install-package-done" $pkg.name $elapsed "ms" "metapackage"
}

proc metadata_manifest_paths(metadata: Record) [error] -> Result[List[Path]] {
  let manifest_text: List[Str] = metadata.get("manifest")?
  var manifest = [fp"${rel_text}" for rel_text in manifest_text]
  manifest
}

proc metadata_etcsums(metadata: Record) [error] -> Result[List[types.EtcSum]] {
  let files: List[Record] = metadata.get("files")?
  var sums = []

  for file in files {
    let path_text: Str = file.get("path")?
    let kind: Str = file.get("kind")?
    let sha256: Str = file.get("sha256")?

    if kind == "file" and util.is_etc_file(fp"${path_text}") {
      sums = sums.push({path: path_text, sha256})
    }
  }

  sums
}

proc load_remote_metadata_sidecar(path_value: Path, pkg: types.RemotePackage) [fs, error] -> Result[Record] {
  let metadata: Record = json.read(path_value)?
  let arch: Str = metadata.get("arch")?
  let name: Str = metadata.get("name")?
  let ver: Str = metadata.get("ver")?
  let rel: Str = metadata.get("rel")?

  if arch != pkg.arch or name != pkg.name or ver != pkg.ver or rel != pkg.rel {
    return Err(
      types.PmError.PackageContract(
        f"${path_value.display()} does not match ${pkg.name} ${util.version_id(pkg.ver, pkg.rel)}",
      ),
    )
  }

  metadata
}

pure metadata_files_key(files: List[Record]) -> Result[Str] {
  var key = ""

  for file in files {
    let path_text: Str = file.get("path")?
    let kind: Str = file.get("kind")?
    let mode: Int = file.get("mode")?
    let sha256: Str = file.get("sha256")?
    let target: Str = file.get("target")?
    key = f"""${key}${path_text}	${kind}	${mode}	${sha256}	${target}
"""
  }

  key
}

proc validate_remote_metadata_sidecar(stage: Path, metadata: Record) [fs, error] -> Result[Bool] {
  let stage_db = util.package_db_path(stage, metadata.get("name")?)
  let staged_manifest = local.load_manifest(stage_db)?
  let metadata_manifest = metadata_manifest_paths(metadata)?
  let staged_files = local.collect_metadata_files(stage, staged_manifest)?
  let metadata_files: List[Record] = metadata.get("files")?

  staged_manifest == metadata_manifest and metadata_files_key(staged_files)? == metadata_files_key(metadata_files)?
}

## Exported PM declaration `install_remote_tarball`.
export proc install_remote_tarball(
  ctx: types.PmContext,
  pkg: types.RemotePackage,
  tarball: Path,
  from_cache: Bool,
  prepared_stage: Path = p"",
  prepared_metadata: Path = p"",
  prepared_metadata_found: Bool = false,
) [fs, net, process, env, time, error] {
  let started = time.now()
  let id = util.package_id(pkg.name, pkg.ver, pkg.rel)
  let install_stage = if prepared_stage.display() == "" { fp"${ctx.work}/${id}-remote-install" } else { prepared_stage }
  let label = if from_cache { "cache-installed" } else { "remote-installed" }
  print --flush ${pkg.name} util.version_id(pkg.ver, pkg.rel) "install:" "starting" $label
  let db = util.package_db_path(ctx.root, pkg.name)
  var manifest = []
  var etcsums = []
  var local_pkg = remote.package_from_remote(pkg)?
  var sidecar_metadata: Record = {}
  let sidecar = if prepared_metadata.display() == "" {
    remote.fetch_remote_metadata_sidecar(ctx.out, pkg)?
  } else {
    {found: prepared_metadata_found, path: prepared_metadata, from_cache: true}
  }
  var have_sidecar = false

  if sidecar.found {
    sidecar_metadata = load_remote_metadata_sidecar(sidecar.path, pkg)?
    manifest = metadata_manifest_paths(sidecar_metadata)?
    etcsums = metadata_etcsums(sidecar_metadata)?
    have_sidecar = true
  } else {
    if prepared_stage.display() == "" {
      fs.remove(install_stage, missing_ok: true)?
      fs.mkdir(install_stage)?
      archive.tar_extract(tarball, install_stage, 0, "auto", true)?
    }

    let stage_db = util.package_db_path(install_stage, pkg.name)
    manifest = local.load_manifest(stage_db)?
    etcsums = json.read(fp"${stage_db}/etcsums.json")?
    local_pkg = local.package_with_extract_install(local_pkg, local.load_extract_install(stage_db)?)
  }

  if have_sidecar and prepared_stage.display() == "" {
    fs.remove(install_stage, missing_ok: true)?
    fs.mkdir(install_stage)?
    archive.tar_extract(tarball, install_stage, 0, "auto", true)?
  }

  if have_sidecar {
    let metadata_matches = validate_remote_metadata_sidecar(install_stage, sidecar_metadata)?

    if ! metadata_matches {
      let stage_db = util.package_db_path(install_stage, pkg.name)
      manifest = local.load_manifest(stage_db)?
      etcsums = json.read(fp"${stage_db}/etcsums.json")?
      local_pkg = local.package_with_extract_install(local_pkg, local.load_extract_install(stage_db)?)
      have_sidecar = false
      print --flush "pm-install-metadata-mismatch" $pkg.name "using tarball metadata"
    }
  }

  let old_manifest = local.load_manifest(db)?
  let old_sums = local.load_etcsums(db)?
  let new_sums = local.map_etcsums(etcsums)?
  let installed_owners = local.load_installed_owners(ctx.root)?

  if have_sidecar and ! fs.exists(db)? {
    extensions.run_lifecycle_hooks("pre-install", pkg.name, ctx, "remote-tarball")?
    local.direct_extract_package(ctx, local_pkg, tarball, manifest, etcsums, installed_owners)?
    extensions.run_lifecycle_hooks("post-install", pkg.name, ctx, "remote-tarball")?
    print ${pkg.name} manifest.len() $label
    let elapsed = time.now() - started
    print --flush "pm-install-package-done" $pkg.name $elapsed "ms" manifest.len() $label
    return
  }

  if local_pkg.extract_install and ! fs.exists(db)? {
    extensions.run_lifecycle_hooks("pre-install", pkg.name, ctx, "remote-tarball")?
    local.direct_extract_package(ctx, local_pkg, tarball, manifest, etcsums, installed_owners)?
    extensions.run_lifecycle_hooks("post-install", pkg.name, ctx, "remote-tarball")?
    print ${pkg.name} manifest.len() $label
    let elapsed = time.now() - started
    print --flush "pm-install-package-done" $pkg.name $elapsed "ms" manifest.len() $label
    return
  }

  local.ensure_installable(ctx.root, local_pkg, manifest, installed_owners)?
  extensions.run_lifecycle_hooks("pre-install", pkg.name, ctx, "remote-tarball")?
  let old_manifest_extra = local.collect_old_manifest_extra(old_manifest, manifest)?

  if old_manifest_extra.len() > 0 {
    let _ = fs.remove_manifest(ctx.root, old_manifest_extra, missing_ok: true)?
  }

  local.install_manifest_entries(ctx.root, install_stage, local_pkg, manifest, old_sums, new_sums, installed_owners)?
  local.write_package_db(ctx.root, local_pkg, manifest, etcsums)?
  extensions.run_lifecycle_hooks("post-install", pkg.name, ctx, "remote-tarball")?
  print ${pkg.name} manifest.len() $label
  let elapsed = time.now() - started
  print --flush "pm-install-package-done" $pkg.name $elapsed "ms" manifest.len() $label
}

proc prepare_remote_install_stage(
  ctx: types.PmContext,
  pkg: types.RemotePackage,
  tarball: Path,
) [fs, error] -> Result[Path] {
  let stage = fp"${ctx.work}/${util.package_id(pkg.name, pkg.ver, pkg.rel)}-remote-install"
  fs.remove(stage, missing_ok: true)?
  fs.mkdir(stage)?
  archive.tar_extract(tarball, stage, 0, "auto", true)?
  stage
}

## Exported PM declaration `install_remote_packages`.
export proc install_remote_packages(ctx: types.PmContext, names: List[Str]) [fs, net, process, env, time, error] {
  let install_started = time.now()
  let index = remote.ensure_remote_index(ctx.out)?
  let selected = remote.collect_remote_packages(ctx.root, index, names)?
  let ordered = remote.order_remote_packages(ctx.root, selected)?
  let tarball_packages = ordered |> where ! .metapackage
  var tarballs: Map[Path] = {}
  var tarball_from_cache: Map[Bool] = {}
  var prepared_stages: Map[Path] = {}
  var prepared_metadata: Map[Path] = {}
  var prepared_metadata_found: Map[Bool] = {}

  if tarball_packages.len() > 0 {
    let download_started = time.now()
    let downloaded = tarball_packages
      |> par-map --jobs=tarball_packages.len() { |pkg|
        let tarball = remote.download_remote_tarball(ctx.out, pkg)?
        let metadata = remote.fetch_remote_metadata_sidecar(ctx.out, pkg)?

        if metadata.found {
          load_remote_metadata_sidecar(metadata.path, pkg)?
        }

        {
          name: pkg.name,
          tarball: tarball.tarball,
          from_cache: tarball.from_cache,
          metadata: metadata.path,
          metadata_found: metadata.found,
        }
      }

    for item in downloaded {
      tarballs[item.name] = item.tarball
      tarball_from_cache[item.name] = item.from_cache
      prepared_metadata[item.name] = item.metadata
      prepared_metadata_found[item.name] = item.metadata_found
    }

    let download_elapsed = time.now() - download_started
    print --flush "pm-install-download-done" $download_elapsed "ms" tarball_packages.len() packages

    let staging_started = time.now()
    let prepared = tarball_packages
      |> par-map --jobs=tarball_packages.len() { |pkg|
        prepare_remote_install_stage(ctx, pkg, tarballs.get(pkg.name)?)?
      }

    var prepared_index = 0
    for pkg in tarball_packages {
      prepared_stages[pkg.name] = prepared[prepared_index]
      prepared_index += 1
    }

    let staging_elapsed = time.now() - staging_started
    print --flush "pm-install-staging-done" $staging_elapsed "ms" tarball_packages.len() packages
  }

  let commit_started = time.now()
  for pkg in ordered {
    if pkg.metapackage {
      install_remote_metapackage(ctx, pkg)?
    } else {
      let tarball = tarballs.get(pkg.name)?
      let from_cache = tarball_from_cache.get(pkg.name, false)
      install_remote_tarball(
        ctx,
        pkg,
        tarball,
        from_cache,
        prepared_stages.get(pkg.name, p""),
        prepared_metadata.get(pkg.name, p""),
        prepared_metadata_found.get(pkg.name, false),
      )?
    }
  }

  let commit_elapsed = time.now() - commit_started
  let install_elapsed = time.now() - install_started
  print --flush "pm-install-commit-done" $commit_elapsed "ms" ordered.len() packages
  print --flush "pm-install-remote-done" $install_elapsed "ms" ordered.len() packages
}

## Exported PM declaration `install_built_packages`.
export proc install_built_packages(ctx: types.PmContext, built: List[types.BuiltPackage]) [fs, process, env, error] {
  for item in built {
    let install_stage = fp"${ctx.work}/${item.id}-install"
    fs.remove(install_stage, missing_ok: true)?
    fs.mkdir(install_stage)?
    archive.tar_extract(item.tarball, install_stage, 0, "auto", true)?
    let db = util.package_db_path(ctx.root, item.pkg.name)
    let old_manifest = local.load_manifest(db)?
    let old_sums = local.load_etcsums(db)?
    let new_sums = local.map_etcsums(item.etcsums)?
    let installed_owners = local.load_installed_owners(ctx.root)?

    if item.pkg.extract_install and ! fs.exists(db)? {
      extensions.run_lifecycle_hooks("pre-install", item.pkg.name, ctx, "local")?
      local.call_pkg_hook(item.pkg, "pre_install", ctx.root)?
      local.direct_extract_package(ctx, item.pkg, item.tarball, item.manifest, item.etcsums, installed_owners)?
      local.call_pkg_hook(item.pkg, "post_install", ctx.root)?
      extensions.run_lifecycle_hooks("post-install", item.pkg.name, ctx, "local")?
      print ${item.pkg.name} item.manifest.len() archive.tar_list(item.tarball)?.collect().len() installed
      continue
    }

    local.ensure_installable(ctx.root, item.pkg, item.manifest, installed_owners)?
    extensions.run_lifecycle_hooks("pre-install", item.pkg.name, ctx, "local")?
    local.call_pkg_hook(item.pkg, "pre_install", ctx.root)?
    let old_manifest_extra = local.collect_old_manifest_extra(old_manifest, item.manifest)?
    let _ = fs.remove_manifest(ctx.root, old_manifest_extra, missing_ok: true)?
    local.install_manifest_entries(
      ctx.root,
      install_stage,
      item.pkg,
      item.manifest,
      old_sums,
      new_sums,
      installed_owners,
    )?
    local.write_package_db(ctx.root, item.pkg, item.manifest, item.etcsums)?
    local.call_pkg_hook(item.pkg, "post_install", ctx.root)?
    extensions.run_lifecycle_hooks("post-install", item.pkg.name, ctx, "local")?
    print ${item.pkg.name} item.manifest.len() archive.tar_list(item.tarball)?.collect().len() installed
  }
}

## Exported PM declaration `collect_installed_names`.
export proc collect_installed_names(root: Path) [fs, error] -> Result[List[Str]] {
  var names = []
  let packages_db = util.packages_db_path(root)

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

## Exported PM declaration `ensure_no_dependents`.
export proc ensure_no_dependents(root: Path, names: List[Str]) [fs, error] {
  let installed_names = collect_installed_names(root)?

  for installed in installed_names {
    if installed not in names {
      let metadata = local.load_metadata(util.package_db_path(root, installed))?
      let deps: List[Str] = metadata.get("deps")?

      for target in names {
        if target in deps {
          return Err(types.PmError.DependentPackage(f"${installed} depends on ${target}"))
        }
      }
    }
  }
}

## Exported PM declaration `remove_installed_package`.
export proc remove_installed_package(ctx: types.PmContext, name: Str) [fs, process, env, error] {
  let db = util.package_db_path(ctx.root, name)

  if ! fs.exists(db)? {
    return Err(types.PmError.PackageNotInstalled(f"${name} is not installed"))
  }

  let metadata = local.load_metadata(db)?
  extensions.run_lifecycle_hooks("pre-remove", name, ctx, "")?
  local.call_installed_hook(metadata, "pre_remove", ctx.root)?
  let manifest = local.load_manifest(db)?
  let etcsums = local.load_etcsums(db)?
  let removable = local.collect_removable_manifest(ctx.root, manifest, etcsums)?
  let removed = fs.remove_manifest(ctx.root, removable, missing_ok: true)?
  fs.remove(db, missing_ok: true)?
  local.call_installed_hook(metadata, "post_remove", ctx.root)?
  extensions.run_lifecycle_hooks("post-remove", name, ctx, "")?
  print ${name} ${removed.removed} "removed"
}

## Exported PM declaration `remove_installed_packages`.
export proc remove_installed_packages(ctx: types.PmContext, names: List[Str]) [fs, process, env, error] {
  ensure_no_dependents(ctx.root, names)?

  for name in names {
    remove_installed_package(ctx, name)?
  }
}

## Exported PM declaration `remove_built_packages`.
export proc remove_built_packages(ctx: types.PmContext, built: List[types.BuiltPackage]) [fs, process, env, error] {
  for item in built {
    remove_installed_package(ctx, item.pkg.name)?
  }
}

## Exported PM declaration `print_installed_list`.
export proc print_installed_list(root: Path) [fs, error] {
  let installed_names = collect_installed_names(root)?

  for name in installed_names {
    let metadata = local.load_metadata(util.package_db_path(root, name))?
    let ver: Str = metadata.get("ver")?
    let rel: Str = metadata.get("rel")?
    print ${name} util.version_id(ver, rel)
  }
}

## Exported PM declaration `print_package_info`.
export proc print_package_info(root: Path, name: Str) [fs, error] {
  let db = util.package_db_path(root, name)

  if ! fs.exists(db)? {
    return Err(types.PmError.PackageNotInstalled(f"${name} is not installed"))
  }

  let metadata = local.load_metadata(db)?
  let ver: Str = metadata.get("ver")?
  let rel: Str = metadata.get("rel")?
  let deps: List[Str] = metadata.get("deps")?
  let mkdeps_host: List[Str] = metadata.get("mkdeps_host")?
  let empty_mkdeps_target = []
  let mkdeps_target = if metadata.has("mkdeps_target") { metadata.get("mkdeps_target")? } else { empty_mkdeps_target }
  let manifest = local.load_manifest(db)?
  print ${name} util.version_id(ver, rel)
  print "deps" deps.join(" ")
  print "mkdeps_host" mkdeps_host.join(" ")
  print "mkdeps_target" mkdeps_target.join(" ")
  print "files" manifest.len()
}

proc installed_package_deps(root: Path, name: Str) [fs, error] -> Result[List[Str]] {
  let db = util.package_db_path(root, name)

  if ! fs.exists(db)? {
    return Err(types.PmError.MissingDependency(f"${name} is not installed"))
  }

  let metadata = local.load_metadata(db)?
  metadata.get("deps")?
}

## Exported PM declaration `tree_branch`.
export pure tree_branch(last: Bool) -> Str {
  if last {
    return "`-- "
  }

  return "|-- "
}

## Exported PM declaration `tree_child_prefix`.
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

## Exported PM declaration `collect_installed_tree_roots`.
export proc collect_installed_tree_roots(root: Path) [fs, error] -> Result[List[Str]] {
  let installed_names = collect_installed_names(root)?
  var depended: Map[Bool] = {}

  for name in installed_names {
    let deps = installed_package_deps(root, name)?

    for dep in deps {
      if dep in installed_names {
        depended[dep] = true
      } else {
        return Err(types.PmError.MissingDependency(f"${name} depends on missing ${dep}"))
      }
    }
  }

  var roots = [name for name in installed_names if ! depended.get(name, false)]
  roots
}

## Exported PM declaration `print_dependency_tree`.
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

## Exported PM declaration `print_outdated`.
export proc print_outdated(root: Path, packages: List[types.Package]) [fs, error] {
  for pkg in packages {
    let db = util.package_db_path(root, pkg.name)

    if fs.exists(db)? {
      let metadata = local.load_metadata(db)?
      let ver: Str = metadata.get("ver")?
      let rel: Str = metadata.get("rel")?

      if ver != pkg.ver or rel != pkg.rel {
        print ${pkg.name} util.version_id(ver, rel) "->" util.version_id(pkg.ver, pkg.rel)
      }
    }
  }
}

## Exported PM declaration `print_search_matches`.
export proc print_search_matches(root: Path, query: Str, packages: List[types.Package]) [fs, error] {
  for pkg in packages {
    if query in pkg.name {
      print ${pkg.name} util.version_id(pkg.ver, pkg.rel) "local"
    }
  }

  let installed_names = collect_installed_names(root)?

  for name in installed_names {
    if query in name {
      let metadata = local.load_metadata(util.package_db_path(root, name))?
      let ver: Str = metadata.get("ver")?
      let rel: Str = metadata.get("rel")?
      print ${name} util.version_id(ver, rel) "installed"
    }
  }
}
