#!/usr/bin/env -S XSH_MODULE_PATH=.:/usr/lib/pm xsh --
use pm.extensions
use pm.local
use pm.remote
use pm.types
use pm.util

pure usage(message: Str) -> Error {
  PmError.Usage(f"usage: ${message}")
}

proc print_help() [] {
  print "usage: pm COMMAND [ARG...]\n\ntop-level commands:\n  build REPO_DIR PKGDIR...\n  world-plan PKGDIR... [--arch ARCH] [--build] [--upload] [--sync-rels] [--to-tranche N] [-j N|--jobs N]\n  build-install ROOT BUILD_ROOT WORK OUT PKGDIR...\n  build-set REPO_DIR PKGDIR...\n  build-upload-set REPO_DIR PKGDIR...\n  upload-set REPO_DIR PKGDIR...\n  upload-repo-export REPO_DIR\n\nroot commands:\n  install [ROOT WORK OUT] PKG...\n  remove [ROOT WORK OUT] PKG...\n  list [ROOT WORK OUT]\n  info [ROOT WORK OUT] PKG...\n  tree [ROOT WORK OUT] [PKG...]\n  search [ROOT WORK OUT] QUERY [PKGDIR...]\n  outdated [ROOT WORK OUT] PKGDIR...\n  update [ROOT WORK OUT] PKGDIR...\n  upgrade [ROOT WORK OUT] PKGDIR...\n  checksum [ROOT WORK OUT] PKGDIR...\n  update-checksums [ROOT WORK OUT] PKGDIR...\n  download [ROOT WORK OUT] PKGDIR...\n  refresh-index [ROOT WORK OUT]\n  auth [ROOT WORK OUT] [TOKEN]\n  upload [ROOT WORK OUT] PKGDIR...\n  help-ext [ROOT WORK OUT]\n\nWhen run from inside this package repo, root commands default ROOT, WORK, and OUT\nto .root, .work, and .out at the repo root.\n\nworld-plan stores its staging repo under ~/.cache/laputa/world-<hash>, where\nthe hash covers the selected package set and arch. The state fingerprint covers\nselected PKGBUILD.xsh files so package edits invalidate an in-progress world.\n"
}

type WorldPlanOptions = {
  pkgdirs: List[Str],
  arch: Str,
  build: Bool,
  upload: Bool,
  sync_rels: Bool,
  to_tranche: Int,
  jobs: Int,
}

proc build_local_packages(
  ctx: PmContext,
  raw: List[Str],
  allow_installed_deps: Bool,
) [fs, net, process, env, time, error] -> Result[List[BuiltPackage]] {
  let dirs = paths_from_args(raw)?
  let packages = load_package_dirs(dirs)?
  let ordered = order_packages(ctx.root, packages, allow_installed_deps)?
  build_packages(ctx, ordered)?
}

proc build_and_install_local_packages(
  ctx: PmContext,
  raw: List[Str],
  allow_installed_deps: Bool,
) [fs, net, process, env, time, error] {
  let built = build_local_packages(ctx, raw, allow_installed_deps)?
  install_built_packages(ctx, built)?
}

proc order_repo_build_packages(
  root: Path,
  packages: List[Package],
  index: List[RemotePackage],
) [fs, env, error] -> Result[List[Package]] {
  var ordered: List[Package] = []
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

pure world_dependency_is_seeded(pkg: Package, dep: Str, cross_build: Bool) -> Bool {
  ! cross_build and (pkg.name == "musl" and (dep == "llvm-toolchain" or dep == "zlib") or pkg.name == "gnu-stubs" and dep == "llvm-toolchain")
}

proc order_world_build_packages(
  root: Path,
  packages: List[Package],
  index: List[RemotePackage],
  arch: Str,
  include_mkdeps: Bool,
) [fs, env, error] -> Result[List[Package]] {
  var ordered: List[Package] = []
  var local_names: Map[Bool] = {}
  var repo_names: Map[Bool] = {}

  for pkg in packages {
    local_names[pkg.name] = true
  }

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

        for dep in effective_world_seed_dependencies(pkg, include_mkdeps, true) {
          if local_names.get(dep, false) and ! world_dependency_is_seeded(pkg, dep, ! include_mkdeps) {
            if ! added.get(dep, false) {
              ready = false
            }
          } else if ! world_dependency_is_seeded(pkg, dep, ! include_mkdeps) and ! repo_names.get(dep, false) and ! fs.exists(
            package_db_path(root, dep),
          )? {
            return Err(PmError.MissingDependency(f"${pkg.name} depends on missing ${dep}"))
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
      return Err(PmError.DependencyCycle("world package dependency graph did not make progress"))
    }
  }

  ordered
}

proc missing_world_dependencies(
  root: Path,
  deps: List[Str],
  local_names: Map[Bool],
  built_names: Map[Bool],
) [fs, error] -> Result[List[Str]] {
  var missing: List[Str] = []
  var seen: Map[Bool] = {}

  for dep in deps {
    if local_names.get(dep, false) and ! built_names.get(dep, false) {
      return Err(PmError.MissingDependency(f"${dep} has not been built yet"))
    }

    if ! seen.get(dep, false) and ! fs.exists(package_db_path(root, dep))? {
      missing = missing.push(dep)
      seen[dep] = true
    }
  }

  missing
}

proc missing_world_build_dependencies(
  root: Path,
  pkg: Package,
  deps: List[Str],
  local_names: Map[Bool],
  built_names: Map[Bool],
  cross_build: Bool,
) [fs, error] -> Result[List[Str]] {
  var missing: List[Str] = []
  var seen: Map[Bool] = {}

  for dep in deps {
    if local_names.get(dep, false) and ! built_names.get(dep, false) and ! world_dependency_is_seeded(
      pkg,
      dep,
      cross_build,
    ) {
      return Err(PmError.MissingDependency(f"${dep} has not been built yet"))
    }

    if ! seen.get(dep, false) and ! fs.exists(package_db_path(root, dep))? {
      missing = missing.push(dep)
      seen[dep] = true
    }
  }

  missing
}

proc missing_fresh_world_dependencies(
  root: Path,
  deps: List[Str],
  local_names: Map[Bool],
  built_names: Map[Bool],
  remote_latest: Map[RemotePackage],
) [fs, error] -> Result[List[Str]] {
  var missing: List[Str] = []
  var seen: Map[Bool] = {}

  for dep in deps {
    if local_names.get(dep, false) and ! built_names.get(dep, false) {
      return Err(PmError.MissingDependency(f"${dep} has not been built yet"))
    }

    if ! seen.get(dep, false) {
      let db = package_db_path(root, dep)
      var needs_install = ! fs.exists(db)?

      if ! needs_install and remote_latest.has(dep) {
        let remote_pkg: RemotePackage = remote_latest.get(dep)?
        let metadata = load_metadata(db)?
        let ver: Str = metadata.get("ver")?
        let rel: Str = metadata.get("rel")?
        needs_install = compare_version_release(ver, rel, remote_pkg.ver, remote_pkg.rel) < 0
      }

      if needs_install {
        missing = missing.push(dep)
      }

      seen[dep] = true
    }
  }

  missing
}

pure package_exempt_from_implicit_pm(name: Str) -> Bool {
  name == "baselayout" or name == "xsh" or name == "laputa-pm"
}

# Temporary: xsh 0.0.0 is a development marker that should be considered
# newer than any release-* version in the remote index.
pure world_package_always_newer_than_remote(name: Str, ver: Str) -> Bool {
  name == "xsh" and ver == "0.0.0"
}

proc add_implicit_pm_dependency(pkg: Package, deps: List[Str]) [] -> List[Str] {
  if ! package_exempt_from_implicit_pm(pkg.name) and ! deps.contains("laputa-pm") {
    return deps.push("laputa-pm")
  }

  deps
}

proc effective_world_target_dependencies(pkg: Package, include_target_build_deps: Bool) [] -> List[Str] {
  var deps = pkg.deps

  if include_target_build_deps {
    deps = deps.extend(pkg.target_build_deps)
  }

  add_implicit_pm_dependency(pkg, deps)
}

proc effective_world_dependencies(pkg: Package, include_mkdeps: Bool) [] -> List[Str] {
  var deps = effective_world_target_dependencies(pkg, include_mkdeps)

  if include_mkdeps {
    deps = deps.extend(pkg.mkdeps)
  }

  deps
}

proc effective_world_build_dependencies(pkg: Package, cross_build: Bool) [] -> List[Str] {
  if cross_build {
    var deps = pkg.mkdeps

    if pkg.name == "llvm-toolchain" and ! deps.contains("llvm-toolchain") {
      deps = deps.push("llvm-toolchain")
    }

    return deps
  }

  effective_world_dependencies(pkg, true)
}

proc copy_world_seed_path(source_root: FsRoot, dest_root: FsRoot, rel_path: Path) [fs, error] {
  match fs.root_readlink(source_root, rel_path) {
    Ok(target) => {
      fs.root_symlink(dest_root, target, rel_path, overwrite: true)?
      return
    }
    Err(_) => {}
  }

  let meta = fs.root_metadata(source_root, rel_path)?

  if meta.kind == "file" {
    fs.root_install_file(source_root, rel_path, dest_root, rel_path, meta.mode % 4096, overwrite: true)?
  }
}

proc copy_world_seed_package(source_root: Path, dest_root: Path, name: Str) [fs, error] {
  let source_db = package_db_path(source_root, name)
  let dest_db = package_db_path(dest_root, name)
  let manifest = load_manifest(source_db)?
  let source_handle = fs.open_root(source_root)?
  defer fs.close_root(source_handle)
  let dest_handle = fs.open_root(dest_root)?
  defer fs.close_root(dest_handle)

  for rel_path in manifest {
    copy_world_seed_path(source_handle, dest_handle, rel_path)?
  }

  let _ = fs.copy_tree(source_db, dest_db, parents: true, overwrite: true)?
}

proc seed_world_package_dependency_set(staged_root: Path, package_root: Path, owner: Str, deps: List[Str]) [fs, error] {
  var names = ["baselayout", "xsh", "laputa-pm", "zlib"]
  var required = [false, false, false, false]

  for dep in deps {
    names = names.push(dep)
    required = required.push(true)
  }

  var copied: Map[Bool] = {}
  var index = 0

  while index < names.len() {
    let name = names[index]
    let is_required = required[index]

    if ! copied.get(name, false) {
      let db = package_db_path(staged_root, name)

      if fs.exists(db)? {
        copy_world_seed_package(staged_root, package_root, name)?
        copied[name] = true
        let metadata = load_metadata(db)?
        let package_deps: List[Str] = metadata.get("deps")?

        for dep in package_deps {
          if ! copied.get(dep, false) {
            names = names.push(dep)
            required = required.push(is_required)
          }
        }
      } else if is_required {
        return Err(PmError.MissingDependency(f"${owner} requires staged ${name}"))
      }
    }

    index += 1
  }

  if ! fs.exists(fp"${package_root}/lib")? and fs.exists(fp"${package_root}/usr/lib")? {
    fs.symlink(p"usr/lib", fp"${package_root}/lib")?
  }
}

proc effective_world_seed_dependencies(
  pkg: Package,
  include_mkdeps: Bool,
  include_target_build_deps: Bool,
) [] -> List[Str] {
  var deps = effective_world_target_dependencies(pkg, include_target_build_deps)

  if include_mkdeps {
    deps = deps.extend(pkg.mkdeps)
  }

  deps
}

proc seed_world_package_root(
  staged_root: Path,
  package_root: Path,
  pkg: Package,
  include_mkdeps: Bool,
  include_target_build_deps: Bool,
) [fs, error] {
  seed_world_package_dependency_set(
    staged_root,
    package_root,
    pkg.name,
    effective_world_seed_dependencies(pkg, include_mkdeps, include_target_build_deps),
  )?
}

proc seed_world_package_tool_root(staged_root: Path, package_root: Path, pkg: Package) [fs, error] {
  seed_world_package_dependency_set(staged_root, package_root, pkg.name, pkg.mkdeps)?
}

pure world_state_path(repo_dir: Path) -> Path {
  fp"${repo_dir}/.world/state.json"
}

pure world_package_id(pkg: Package) -> Str {
  package_id(pkg.name, pkg.ver, pkg.rel)
}

proc world_package_rows(packages: List[Package]) [] -> List[Record] {
  var rows: List[Record] = []

  for pkg in packages {
    let sources = [source.display() for source in pkg.sources]

    rows = rows.push(
      {
        name: pkg.name,
        ver: pkg.ver,
        rel: pkg.rel,
        id: world_package_id(pkg),
        dir: pkg.dir.display(),
        deps: pkg.deps,
        mkdeps: pkg.mkdeps,
        target_build_deps: pkg.target_build_deps,
        sources,
        checksums: pkg.checksums,
      },
    )
  }

  rows
}

proc pm_module_root_path() [fs, env, error] -> Result[Path] {
  for entry in (env.get("XSH_MODULE_PATH") ?? "").split(":") {
    let raw = entry.trim()

    if raw != "" {
      let candidate = fp"${raw}"

      if fs.exists(fp"${candidate}/pm.xsh")? and fs.exists(fp"${candidate}/pm")? {
        return path.absolute(candidate)?
      }
    }
  }

  for candidate in [p".", p"laputa", /usr/lib/pm] {
    if fs.exists(fp"${candidate}/pm.xsh")? and fs.exists(fp"${candidate}/pm")? {
      return path.absolute(candidate)?
    }
  }

  return Err(PmError.PackageContract("cannot find PM module root"))
}

proc append_fingerprint_file(body: Str, label: Str, path_value: Path) [fs, error] -> Result[Str] {
  let meta = fs.metadata(path_value)?

  if meta.kind == "symlink" {
    return f"""${body}symlink	${label}	${path_value.readlink()?.display()}
"""
  }

  if meta.kind == "file" {
    return f"""${body}file	${label}	${hash.sha256(path_value)?.hex()}
"""
  }

  body
}

proc world_plan_content_hash(packages: List[Package], arch: Str) [fs, error] -> Result[Str] {
  var body = f"""arch	${arch}
"""

  let sorted = packages |> sort-by .name

  for pkg in sorted {
    body = append_fingerprint_file(body, f"pkg/${pkg.name}/PKGBUILD.xsh", fp"${pkg.dir}/PKGBUILD.xsh")?
  }

  bytes.from_text(body).sha256().hex()
}

proc world_plan_cache_key(packages: List[Package], arch: Str) [] -> Str {
  var body = f"""arch	${arch}
"""

  let sorted = packages |> sort-by .name

  for pkg in sorted {
    body = f"""${body}pkg	${pkg.name}
"""
  }

  bytes.from_text(body).sha256().hex()
}

proc world_cache_repo_dir(cache_key: Str) [env, error] -> Result[Path] {
  let home = (env.get("HOME") ?? "").trim()

  if home == "" {
    return Err(PmError.PackageContract("HOME is required for world-plan cache"))
  }

  fp"${home}/.cache/laputa/world-${cache_key}"
}

proc expand_world_package_dirs(raw: List[Str]) [fs, error] -> Result[List[Path]] {
  var dirs: List[Path] = []
  var seen: Map[Bool] = {}

  for item in raw {
    let input = path.absolute(fp"${item}")?
    let pkgbuild = fp"${input}/PKGBUILD.xsh"

    if fs.exists(pkgbuild)? {
      let key = input.display()

      if ! seen.get(key, false) {
        dirs = dirs.push(input)
        seen[key] = true
      }
    } else {
      var children = [child.path for child in fs.children(input)? if child.kind == "dir" and fs.exists(
        fp"${child.path}/PKGBUILD.xsh",
      )?]

      children = children |> sort-by .display()

      if children.len() == 0 {
        return Err(PmError.PackageContract(f"${input.display()} is not a package dir or package root"))
      }

      for child in children {
        let key = child.display()

        if ! seen.get(key, false) {
          dirs = dirs.push(child)
          seen[key] = true
        }
      }
    }
  }

  dirs
}

proc world_local_dependency_names(pkg: Package, local_names: Map[Bool]) [] -> List[Str] {
  var names: List[Str] = []
  var seen: Map[Bool] = {}

  for dep in effective_world_dependencies(pkg, true) {
    if local_names.get(dep, false) and ! seen.get(dep, false) and ! world_dependency_is_seeded(pkg, dep, false) {
      names = names.push(dep)
      seen[dep] = true
    }
  }

  names
}

proc world_plan_levels(ordered: List[Package], local_names: Map[Bool]) [] -> Map[Int] {
  var levels: Map[Int] = {}

  for pkg in ordered {
    var level = 0

    for dep in world_local_dependency_names(pkg, local_names) {
      let dep_level = levels.get(dep, 0)

      if dep_level + 1 > level {
        level = dep_level + 1
      }
    }

    levels[pkg.name] = level
  }

  levels
}

pure ansi(enabled: Bool, code: Str, text: Str) -> Str {
  if enabled {
    return f"[${code}m${text}[0m"
  }

  text
}

proc color_enabled() [env] -> Bool {
  (env.get("NO_COLOR") ?? "").trim() == ""
}

pure package_count_text(count: Int) -> Str {
  if count == 1 {
    return "1 package"
  }

  f"${count} packages"
}

proc world_plan_max_level(ordered: List[Package], levels: Map[Int]) [] -> Int {
  var max_level = 0

  for pkg in ordered {
    let level = levels.get(pkg.name, 0)

    if level > max_level {
      max_level = level
    }
  }

  max_level
}

proc world_packages_at_level(ordered: List[Package], levels: Map[Int], level: Int) [] -> List[Package] {
  var tranche = [pkg for pkg in ordered if levels.get(pkg.name, 0) == level]
  tranche
}

proc validate_world_arch(arch: Str) [error] -> Result[Str] {
  let normalized = normalize_arch(arch)

  if normalized == "aarch64" or normalized == "x86_64" {
    return normalized
  }

  return Err(PmError.Usage(f"unsupported world-plan arch ${arch}; expected aarch64 or x86_64"))
}

proc host_world_arch() [env, error] -> Result[Str] {
  let os = system.uname()?
  validate_world_arch(os.machine)
}

proc world_plan_remote_annotation(
  pkg: Package,
  planned: Package,
  remote_latest: Map[RemotePackage],
) [error] -> Result[Str] {
  if ! remote_latest.has(pkg.name) {
    return ""
  }

  if world_package_always_newer_than_remote(pkg.name, pkg.ver) {
    return ""
  }

  let remote_pkg: RemotePackage = remote_latest.get(pkg.name)?
  let cmp = compare_version_release(planned.ver, planned.rel, remote_pkg.ver, remote_pkg.rel)

  if cmp >= 0 {
    return ""
  }

  f"remote newer ${version_id(remote_pkg.ver, remote_pkg.rel)}"
}

proc planned_world_packages(
  ordered: List[Package],
  local_names: Map[Bool],
  remote_latest: Map[RemotePackage],
  state_planned_rels: Map[Str],
) [error] -> Result[List[Package]] {
  var planned: List[Package] = []
  var changed: Map[Bool] = {}

  for pkg in ordered {
    var planned_pkg = pkg
    var changed_dep = false

    for dep in world_local_dependency_names(pkg, local_names) {
      if changed.get(dep, false) {
        changed_dep = true
      }
    }

    if remote_latest.has(pkg.name) {
      let remote_pkg: RemotePackage = remote_latest.get(pkg.name)?

      if compare_version_text(pkg.ver, remote_pkg.ver) == 0 {
        if state_planned_rels.has(pkg.name) {
          let state_rel = state_planned_rels.get(pkg.name)?
          let planned_rel = if compare_version_text(pkg.rel, state_rel) > 0 { pkg.rel } else { state_rel }
          let remote_to_planned = compare_version_text(remote_pkg.rel, planned_rel)

          if remote_to_planned < 0 or remote_to_planned == 0 and ! changed_dep {
            planned_pkg = package_with_rel(pkg, planned_rel)
          } else {
            let rel_cmp = compare_version_text(planned_pkg.rel, remote_pkg.rel)

            if rel_cmp < 0 or changed_dep and rel_cmp <= 0 {
              planned_pkg = package_with_rel(pkg, next_world_rel(remote_pkg.rel))
            }
          }
        } else {
          let rel_cmp = compare_version_text(planned_pkg.rel, remote_pkg.rel)

          if rel_cmp < 0 or changed_dep and rel_cmp <= 0 {
            planned_pkg = package_with_rel(pkg, next_world_rel(remote_pkg.rel))
          }
        }
      }

      changed[pkg.name] = compare_version_release(planned_pkg.ver, planned_pkg.rel, remote_pkg.ver, remote_pkg.rel) != 0
    } else {
      if state_planned_rels.has(pkg.name) {
        let state_rel = state_planned_rels.get(pkg.name)?

        if compare_version_text(pkg.rel, state_rel) <= 0 {
          planned_pkg = package_with_rel(pkg, state_rel)
        }
      }

      changed[pkg.name] = true
    }

    planned = planned.push(planned_pkg)
  }

  planned
}

proc planned_world_package_map(planned: List[Package]) [] -> Map[Package] {
  var packages = {pkg.name: pkg for pkg in planned}
  packages
}

proc world_plan_version_text(
  pkg: Package,
  planned: Package,
  remote_latest: Map[RemotePackage],
  colors: Bool,
) [error] -> Result[Str] {
  let current = version_id(pkg.ver, pkg.rel)
  let next = version_id(planned.ver, planned.rel)

  if current == next {
    if remote_latest.has(pkg.name) {
      let rpkg: RemotePackage = remote_latest.get(pkg.name)?

      if compare_version_release(rpkg.ver, rpkg.rel, planned.ver, planned.rel) < 0 or world_package_always_newer_than_remote(
        pkg.name,
        planned.ver,
      ) {
        return f"${ansi(colors, "2", version_id(rpkg.ver, rpkg.rel))} ${ansi(colors, "1;33", "->")} ${ansi(
          colors,
          "1;33",
          next,
        )}"
      }
    }

    return ansi(colors, "2", current)
  }

  f"${ansi(colors, "2", current)} ${ansi(colors, "1;33", "->")} ${ansi(colors, "1;33", next)}"
}

pure rel_field_line(line: Str) -> Bool {
  line.starts_with("export let rel ") or line.starts_with("export let rel:") or line.starts_with("export let rel=")
}

proc sync_package_rel(pkg: Package, planned: Package) [fs, error] -> Result[Bool] {
  if pkg.rel == planned.rel {
    return false
  }

  let pkgbuild = fp"${pkg.dir}/PKGBUILD.xsh"
  let lines = fs.read_text(pkgbuild)?.split("\n")
  var output: List[Str] = []
  var found = false

  for line in lines {
    let trimmed = line.trim()

    if rel_field_line(trimmed) {
      if found {
        return Err(PmError.PackageContract(f"${pkg.name} has multiple rel declarations"))
      }

      found = true
      output = output.push(f"export let rel: Str = \"${planned.rel}\"")
    } else {
      output = output.push(line)
    }
  }

  if ! found {
    return Err(PmError.PackageContract(f"${pkg.name} has no rel declaration"))
  }

  fs.write(pkgbuild, output.join("\n"))?
  true
}

proc verify_planned_rels_published(
  packages: List[Package],
  planned_by_name: Map[Package],
  remote_latest: Map[RemotePackage],
) [error] {
  for pkg in packages {
    let planned: Package = planned_by_name.get(pkg.name)?

    if ! remote_latest.has(pkg.name) {
      return Err(PmError.RemotePackage(f"${pkg.name} ${version_id(planned.ver, planned.rel)} is not in remote index"))
    }

    let rpkg: RemotePackage = remote_latest.get(pkg.name)?

    if compare_version_release(rpkg.ver, rpkg.rel, planned.ver, planned.rel) != 0 {
      return Err(
        PmError.RemotePackage(
          f"${pkg.name} planned ${version_id(planned.ver, planned.rel)} but remote has ${version_id(
            rpkg.ver,
            rpkg.rel,
          )}",
        ),
      )
    }
  }
}

proc sync_world_rels(
  ordered: List[Package],
  planned_by_name: Map[Package],
  remote_latest: Map[RemotePackage],
) [fs, error] {
  verify_planned_rels_published(ordered, planned_by_name, remote_latest)?
  var changed = 0

  for pkg in ordered {
    let planned: Package = planned_by_name.get(pkg.name)?

    if sync_package_rel(pkg, planned)? {
      changed += 1
      print ${pkg.name} version_id(pkg.ver, pkg.rel) "->" version_id(planned.ver, planned.rel) "rel-synced"
    }
  }

  print f"world-plan rel sync complete ${changed} changed"
}

proc print_world_plan(
  ordered: List[Package],
  planned: List[Package],
  local_names: Map[Bool],
  world_jobs: Int,
  remote_latest: Map[RemotePackage],
  arch: Str,
) [env, error] {
  let levels = world_plan_levels(ordered, local_names)
  let max_level = world_plan_max_level(ordered, levels)
  let colors = color_enabled()
  let planned_by_name = planned_world_package_map(planned)

  print --flush f"${ansi(colors, "1;36", "world-plan")} ${arch} ${package_count_text(ordered.len())} ${ansi(
    colors,
    "2",
    f"jobs ${world_jobs}",
  )}"

  var level = 0

  while level <= max_level {
    let tranche = world_packages_at_level(ordered, levels, level)
    print --flush f"${ansi(colors, "1;35", f"tranche ${level}")} ${ansi(colors, "2", package_count_text(tranche.len()))}"

    for pkg in tranche {
      let planned_pkg: Package = planned_by_name.get(pkg.name)?
      let annotation = world_plan_remote_annotation(pkg, planned_pkg, remote_latest)?
      let suffix = if annotation == "" { "" } else { f" ${ansi(colors, "1;31", annotation)}" }
      print --flush f"  ${ansi(colors, "1;32", pkg.name)} ${world_plan_version_text(pkg, planned_pkg, remote_latest, colors)?}${suffix}"
    }

    level += 1
  }
}

proc parse_world_jobs(value: Str, source: Str) [error] -> Result[Int] {
  let parsed = value.parse_int()?

  if parsed <= 0 {
    return Err(PmError.Usage(f"${source} must be a positive integer"))
  }

  parsed
}

proc parse_world_to_tranche(value: Str, source: Str) [error] -> Result[Int] {
  let parsed = value.parse_int()?

  if parsed < -1 {
    return Err(PmError.Usage(f"${source} must be -1, zero, or a positive integer"))
  }

  parsed
}

proc default_world_jobs() [env, error] -> Result[Int] {
  let value = (env.get("XSH_PM_WORLD_JOBS") ?? "").trim()

  if value != "" {
    return parse_world_jobs(value, "XSH_PM_WORLD_JOBS")?
  }

  cpu.count()
}

proc compare_lex(left: Str, right: Str) [] -> Int {
  if left == right {
    return 0
  }

  let sorted = [left, right] |> sort-by .

  if sorted[0] == left {
    return -1
  }

  1
}

proc version_parts(value: Str) [] -> List[Str] {
  value.replace("-", ".").replace("_", ".").replace("+", ".").split(".")
}

proc int_text(value: Int) [] -> Str {
  f"${value}"
}

proc compare_version_part(left: Str, right: Str) [] -> Int {
  let left_num = left.parse_int() ?? -1
  let right_num = right.parse_int() ?? -1
  let left_is_num = int_text(left_num) == left
  let right_is_num = int_text(right_num) == right

  if left_is_num and right_is_num {
    if left_num < right_num {
      return -1
    }

    if left_num > right_num {
      return 1
    }

    return 0
  }

  compare_lex(left, right)
}

proc compare_version_text(left: Str, right: Str) [] -> Int {
  let left_parts = version_parts(left)
  let right_parts = version_parts(right)
  let total = if left_parts.len() > right_parts.len() { left_parts.len() } else { right_parts.len() }
  var index = 0

  while index < total {
    let cmp = compare_version_part(left_parts.get(index, "0"), right_parts.get(index, "0"))

    if cmp != 0 {
      return cmp
    }

    index += 1
  }

  0
}

proc compare_version_release(left_ver: Str, left_rel: Str, right_ver: Str, right_rel: Str) [] -> Int {
  let ver_cmp = compare_version_text(left_ver, right_ver)

  if ver_cmp != 0 {
    return ver_cmp
  }

  compare_version_text(left_rel, right_rel)
}

proc validate_world_remote_versions(packages: List[Package], remote_index: List[RemotePackage]) [env, error] {
  let arch = machine_arch()?

  for pkg in packages {
    var found = false
    var remote_ver = ""
    var remote_rel = ""

    for entry in remote_index {
      if entry.arch == arch and entry.name == pkg.name {
        if ! found or compare_version_release(entry.ver, entry.rel, remote_ver, remote_rel) > 0 {
          found = true
          remote_ver = entry.ver
          remote_rel = entry.rel
        }
      }
    }

    if found and compare_version_release(pkg.ver, pkg.rel, remote_ver, remote_rel) <= 0 {
      return Err(
        PmError.PackageContract(
          f"${pkg.name} ${version_id(pkg.ver, pkg.rel)} is not newer than remote ${version_id(remote_ver, remote_rel)}",
        ),
      )
    }
  }
}

proc validate_world_remote_versions_for_plan(
  packages: List[Package],
  remote_latest: Map[RemotePackage],
  allow_equal: Bool,
) [env, error] {
  for pkg in packages {
    if remote_latest.has(pkg.name) and ! world_package_always_newer_than_remote(pkg.name, pkg.ver) {
      let rpkg: RemotePackage = remote_latest.get(pkg.name)?
      let cmp = compare_version_release(pkg.ver, pkg.rel, rpkg.ver, rpkg.rel)
      let ver_cmp = compare_version_text(pkg.ver, rpkg.ver)

      if ! allow_equal and cmp <= 0 or allow_equal and ver_cmp < 0 {
        return Err(
          PmError.PackageContract(
            f"${pkg.name} ${version_id(pkg.ver, pkg.rel)} is not newer than remote ${version_id(rpkg.ver, rpkg.rel)}",
          ),
        )
      }
    }
  }
}

proc world_remote_has(index: List[RemotePackage], arch: Str, name: Str) [] -> Bool {
  for entry in index {
    if entry.arch == arch and entry.name == name {
      return true
    }
  }

  false
}

proc world_latest_remote_map(index: List[RemotePackage], arch: Str) [error] -> Result[Map[RemotePackage]] {
  var latest: Map[RemotePackage] = {}

  for entry in index {
    if entry.arch == arch {
      if ! latest.has(entry.name) {
        latest[entry.name] = entry
      } else {
        let current: RemotePackage = latest.get(entry.name)?

        if compare_version_release(entry.ver, entry.rel, current.ver, current.rel) > 0 {
          latest[entry.name] = entry
        }
      }
    }
  }

  latest
}

proc world_latest_remote(index: List[RemotePackage], arch: Str, name: Str) [error] -> Result[RemotePackage] {
  var found = false

  var latest: RemotePackage = {
    arch,
    name,
    ver: "",
    rel: "",
    deps: [],
    mkdeps: [],
    target_build_deps: [],
    sha256: "",
    size: 0,
    tarball: "",
    metadata: "",
    source_sha256: "",
    source_tarball: "",
    metapackage: false,
  }

  for entry in index {
    if entry.arch == arch and entry.name == name {
      if ! found or compare_version_release(entry.ver, entry.rel, latest.ver, latest.rel) > 0 {
        found = true
        latest = entry
      }
    }
  }

  if ! found {
    return Err(PmError.RemotePackage(f"${name} for ${arch} is not in the remote index"))
  }

  latest
}

proc next_world_rel(rel: Str) [] -> Str {
  match rel.parse_int() {
    Ok(value) => f"${value + 1}"
    Err(_) => f"${rel}.1"
  }
}

pure package_with_rel(pkg: Package, rel: Str) -> Package {
  {...pkg, rel}
}

proc remote_metadata_sha256(repo: Str, out: Path, entry: RemotePackage) [fs, net, time, error] -> Result[Str] {
  if entry.metadata == "" {
    return ""
  }

  let rel = ensure_relative_path(fp"${entry.metadata}", "remote metadata")?
  let cache = fp"${out}/remote-metadata/${rel.display()}"
  let failure = fetch_repo_file_with_retry(repo, rel, cache, timeout: 60s)?

  if failure != "" {
    return Err(PmError.RemoteFetch(failure))
  }

  let metadata: Record = json.read(cache)?
  metadata.get("metadata_sha256")?
}

type RemoteMetadataHash = {name: Str, sha256: Str}

proc world_remote_metadata_hashes(
  repo: Str,
  out: Path,
  packages: List[Package],
  remote_latest: Map[RemotePackage],
  jobs: Int,
) [fs, net, time, error] -> Result[Map[Str]] {
  var candidates: List[RemotePackage] = []

  if repo == "" {
    let empty: Map[Str] = {}
    return empty
  }

  for pkg in packages {
    if remote_latest.has(pkg.name) {
      let rpkg: RemotePackage = remote_latest.get(pkg.name)?

      if compare_version_text(pkg.ver, rpkg.ver) == 0 and compare_version_text(pkg.rel, rpkg.rel) <= 0 {
        candidates = candidates.push(rpkg)
      }
    }
  }

  if candidates.len() == 0 {
    let empty: Map[Str] = {}
    return empty
  }

  # Metadata files are small; keep the remote preflight from opening too many
  # concurrent HTTP reads before the package scheduler starts real build work.
  let metadata_jobs = if jobs > 8 { 8 } else { jobs }

  let rows: List[RemoteMetadataHash] = candidates
    |> par-map --jobs=metadata_jobs { |entry|
      {name: entry.name, sha256: remote_metadata_sha256(repo, out, entry)?}
    }

  var hashes = {row.name: row.sha256 for row in rows}
  hashes
}

pure native_cross_ldso_name(arch: Str) -> Str {
  if arch == "aarch64" {
    return "ld-musl-aarch64.so.1"
  }

  return f"ld-musl-${arch}.so.1"
}

pure native_cross_compiler_script(real: Path, build_root: Path, target_root: Path, target_arch: Str) -> Str {
  return f"""#!/bin/sh
real='${real.display()}'
build_root='${build_root.display()}'
target_root='${target_root.display()}'
target='${target_arch}-linux-musl'
ldso='/usr/lib/${native_cross_ldso_name(target_arch)}'
builtins="$target_root/usr/lib/libclang_rt.builtins-${target_arch}.a"
builtins_arg=""
if [ -f "$builtins" ]; then
  builtins_arg="$builtins"
fi
export LD_LIBRARY_PATH="$build_root/usr/lib:$build_root/usr/lib/llvm22/lib:$LD_LIBRARY_PATH"
cxx_args=""
cxx_libs=""
case "$real" in
  *clang++*)
    if [ -d "$target_root/usr/lib/llvm22/include/c++/v1" ]; then
      cxx_args="-isystem $target_root/usr/lib/llvm22/include/c++/v1"
    elif [ -d "$build_root/usr/lib/llvm22/include/c++/v1" ]; then
      cxx_args="-isystem $build_root/usr/lib/llvm22/include/c++/v1"
    fi
    if [ -d "$target_root/usr/lib/llvm22/include/${target_arch}-linux-musl/c++/v1" ]; then
      cxx_args="$cxx_args -isystem $target_root/usr/lib/llvm22/include/${target_arch}-linux-musl/c++/v1"
    fi
    cxx_libs="-L$target_root/usr/lib/llvm22/lib -lc++ -lc++abi"
    if [ -f "$target_root/usr/lib/llvm22/lib/libunwind.a" ]; then
      cxx_libs="$cxx_libs $target_root/usr/lib/llvm22/lib/libunwind.a"
    fi
    cxx_libs="$cxx_libs -lm"
    ;;
esac
compile_only=0
shared=0
for arg in "$@"; do
  case "$arg" in
    -c|-S|-E) compile_only=1 ;;
    -shared) shared=1 ;;
  esac
done
if [ "$compile_only" = 1 ]; then
  exec "$real" --target="$target" --sysroot="$target_root" -resource-dir "$build_root/usr/lib/llvm22/lib/clang/22" $cxx_args "$@"
fi
if [ "$shared" = 1 ]; then
  exec "$real" --target="$target" --sysroot="$target_root" -resource-dir "$build_root/usr/lib/llvm22/lib/clang/22" -fuse-ld=lld -nostdlib "$@" -L"$target_root/usr/lib" $cxx_libs $builtins_arg -lc
fi
exec "$real" --target="$target" --sysroot="$target_root" -resource-dir "$build_root/usr/lib/llvm22/lib/clang/22" -fuse-ld=lld -nostdlib "$target_root/usr/lib/Scrt1.o" "$target_root/usr/lib/crti.o" "$@" -L"$target_root/usr/lib" $cxx_libs $builtins_arg -lc "$target_root/usr/lib/crtn.o" -Wl,-dynamic-linker,$ldso
"""
}

proc write_native_cross_tool_shims(build_root: Path, target_root: Path, target_arch: Str) [fs, error] {
  let bin = fp"${build_root}/.native-cross/bin"
  fs.mkdir(bin)?
  let clang = fp"${build_root}/usr/lib/llvm22/bin/clang-22"
  let clangxx = fp"${build_root}/usr/lib/llvm22/bin/clang++"

  for name in ["cc", "clang", "clang-22"] {
    let path_value = fp"${bin}/${name}"
    fs.write(path_value, native_cross_compiler_script(clang, build_root, target_root, target_arch))?
    fs.chmod(path_value, 0o755)?
  }

  for name in ["c++", "clang++"] {
    let path_value = fp"${bin}/${name}"
    fs.write(path_value, native_cross_compiler_script(clangxx, build_root, target_root, target_arch))?
    fs.chmod(path_value, 0o755)?
  }
}

proc build_world_package(
  build_ctx: PmContext,
  target_staged_root: Path,
  build_staged_root: Path,
  pkg: Package,
  target_arch: Str,
  build_arch: Str,
  cross_build: Bool,
) [fs, net, process, env, time, error] -> Result[List[BuiltPackage]] {
  var built: List[BuiltPackage] = []
  print --flush ${pkg.name} world_package_id(pkg) "build:" "starting"
  let package_root = fp"${build_ctx.work}/world-build/${world_package_id(pkg)}/root"
  let package_build_root = fp"${build_ctx.work}/world-build/${world_package_id(pkg)}/build-root"
  let package_work = fp"${build_ctx.work}/world-build/${world_package_id(pkg)}/work"
  let package_out = fp"${build_ctx.work}/world-build/${world_package_id(pkg)}/out"
  let package_ctx: PmContext = {command: build_ctx.command, root: package_root, work: package_work, out: package_out}
  fs.remove(package_root, missing_ok: true)?
  fs.remove(package_build_root, missing_ok: true)?
  fs.remove(package_work, missing_ok: true)?
  fs.remove(package_out, missing_ok: true)?
  fs.mkdir(package_root)?
  fs.mkdir(package_work)?
  fs.mkdir(package_out)?
  seed_world_package_root(target_staged_root, package_root, pkg, ! cross_build, true)?
  let package_path_root = if cross_build { package_build_root } else { package_root }
  var package_path = f"${package_path_root}/usr/bin:${env.get("PATH") ?? ""}"
  let build_chroot = if cross_build { "0" } else { env.get("XSH_PM_BUILD_CHROOT") ?? "1" }

  if cross_build {
    fs.mkdir(package_build_root)?

    seed_world_package_dependency_set(
      build_staged_root,
      package_build_root,
      pkg.name,
      effective_world_build_dependencies(pkg, cross_build),
    )?

    write_native_cross_tool_shims(package_build_root, package_root, target_arch)?
    package_path = f"${package_build_root}/.native-cross/bin:${package_path}"
  }

  env {
    LAPUTA_ROOT = package_root.display()
    PATH = package_path
    XSH_PM_ARCH = target_arch
    XSH_PM_TARGET_ARCH = target_arch
    XSH_PM_BUILD_ARCH = build_arch
    XSH_PM_BUILD_ROOT = package_path_root.display()
    XSH_PM_BUILD_CHROOT = build_chroot
  } {
    built = build_packages(package_ctx, [pkg])?
  } ?

  built
}

proc remove_world_unowned_install_conflicts(root: Path, built: List[BuiltPackage]) [fs, error] {
  let installed_owners = load_installed_owners(root)?

  for item in built {
    for rel_path in item.manifest {
      let key = rel_path.display()

      if ! installed_owners.has(key) {
        fs.remove(fp"${root}/${rel_path}", missing_ok: true)?
      }
    }
  }
}

proc world_stage_package_present(root: Path, name: Str) [fs, error] -> Result[Bool] {
  fs.exists(package_db_path(root, name))?
}

proc world_stage_package_present_in_roots(
  root: Path,
  build_root: Path,
  name: Str,
  cross_build: Bool,
) [fs, error] -> Result[Bool] {
  if ! world_stage_package_present(root, name)? {
    return false
  }

  if cross_build {
    return true
  }

  world_stage_package_present(build_root, name)?
}

proc world_should_install_built_package(root: Path, item: BuiltPackage) [fs, error] -> Result[Bool] {
  true
}

proc install_world_built_packages(ctx: PmContext, built: List[BuiltPackage]) [fs, process, env, error] {
  var installable: List[BuiltPackage] = []

  for item in built {
    if world_should_install_built_package(ctx.root, item)? {
      installable = installable.push(item)
    } else {
      print --flush ${item.pkg.name} world_package_id(item.pkg) "stage:" "skip" "wlroots0.19-mesa"
    }
  }

  if installable.len() > 0 {
    install_built_packages(ctx, installable)?
  }
}

proc read_world_state(repo_dir: Path) [fs, error] -> Result[Record] {
  let state_path = world_state_path(repo_dir)

  if ! fs.exists(state_path)? {
    return Err(PmError.PackageTarball(f"${state_path.display()} is missing; run world-plan --build first"))
  }

  json.read(state_path)?
}

proc write_world_state(
  repo_dir: Path,
  fingerprint: Str,
  packages: List[Package],
  built_names: Map[Bool],
  unchanged_names: Map[Bool],
  complete: Bool,
) [fs, env, error] {
  let state_path = world_state_path(repo_dir)
  fs.mkdir(state_path.parent)?
  let arch = machine_arch()?
  var built: List[Str] = []
  var proofed: List[Str] = []
  var unchanged: List[Str] = []

  for pkg in packages {
    if built_names.get(pkg.name, false) {
      let id = world_package_id(pkg)

      if unchanged_names.get(pkg.name, false) {
        unchanged = unchanged.push(id)
      } else {
        built = built.push(id)
        proofed = proofed.push(id)
      }
    }
  }

  json.write(
    state_path,
    {
      fingerprint,
      arch,
      packages: world_package_rows(packages),
      built,
      proofed,
      unchanged,
      complete,
    },
  )?
}

proc ensure_world_state_compatible(
  repo_dir: Path,
  fingerprint: Str,
  packages: List[Package],
) [fs, env, error] -> Result[Record] {
  let state_path = world_state_path(repo_dir)

  if ! fs.exists(state_path)? {
    let built_names: Map[Bool] = {}
    let unchanged_names: Map[Bool] = {}
    write_world_state(repo_dir, fingerprint, packages, built_names, unchanged_names, false)?
  }

  let state = read_world_state(repo_dir)?
  let stored_fingerprint: Str = state.get("fingerprint")?

  if stored_fingerprint != fingerprint {
    let old_built: List[Str] = state.get("built")?
    let old_proofed: List[Str] = state.get("proofed")?
    let old_unchanged: List[Str] = if state.has("unchanged") { state.get("unchanged")? } else { [] }
    var built_names: Map[Bool] = {}
    var unchanged_names: Map[Bool] = {}

    for pkg in packages {
      let id = world_package_id(pkg)

      if old_unchanged.contains(id) {
        built_names[pkg.name] = true
        unchanged_names[pkg.name] = true
      } else if old_built.contains(id) and old_proofed.contains(id) {
        built_names[pkg.name] = true
      }
    }

    write_world_state(repo_dir, fingerprint, packages, built_names, unchanged_names, false)?
    return read_world_state(repo_dir)?
  }

  state
}

proc world_state_planned_rels(repo_dir: Path, packages: List[Package]) [fs, error] -> Result[Map[Str]] {
  var rels: Map[Str] = {}
  let state_path = world_state_path(repo_dir)

  if ! fs.exists(state_path)? {
    return rels
  }

  let state = read_world_state(repo_dir)?
  var versions = {pkg.name: pkg.ver for pkg in packages}
  let rows: List[Record] = state.get("packages")?

  for row in rows {
    let name: Str = row.get("name")?
    let ver: Str = row.get("ver")?
    let rel: Str = row.get("rel")?

    if versions.has(name) and versions.get(name)? == ver {
      rels[name] = rel
    }
  }

  rels
}

proc find_world_index_entry(index: List[RemotePackage], arch: Str, pkg: Package) [error] -> Result[RemotePackage] {
  for entry in index {
    if entry.arch == arch and entry.name == pkg.name and entry.ver == pkg.ver and entry.rel == pkg.rel {
      return entry
    }
  }

  return Err(
    PmError.RemotePackage(f"${pkg.name} ${version_id(pkg.ver, pkg.rel)} for ${arch} is not in the staged index"),
  )
}

proc verify_staged_entry_tarball(repo_dir: Path, entry: RemotePackage) [fs, error] {
  if entry.metapackage {
    return
  }

  let tarball = fp"${repo_dir}/${entry.tarball}"

  if ! fs.exists(tarball)? {
    return Err(PmError.PackageTarball(f"${tarball.display()} is missing"))
  }

  let metadata = fs.metadata(tarball)?

  if metadata.size != entry.size {
    return Err(PmError.PackageTarball(f"${tarball.display()} size mismatch"))
  }

  let actual = hash.sha256(tarball)?.hex()

  if actual != entry.sha256 {
    return Err(PmError.PackageTarball(f"${tarball.display()} checksum mismatch"))
  }
}

proc verify_staged_entry_metadata(repo_dir: Path, entry: RemotePackage) [fs, error] {
  if entry.metapackage {
    return
  }

  if entry.metadata == "" {
    return Err(PmError.PackageTarball(f"${entry.name} ${version_id(entry.ver, entry.rel)} has no metadata sidecar"))
  }

  let metadata = fp"${repo_dir}/${entry.metadata}"

  if ! fs.exists(metadata)? {
    return Err(PmError.PackageTarball(f"${metadata.display()} is missing"))
  }

  let metadata_record: Record = json.read(metadata)?
  let sidecar_hash: Str = metadata_record.get("metadata_sha256")?

  if sidecar_hash == "" {
    return Err(PmError.PackageTarball(f"${metadata.display()} has empty metadata hash"))
  }
}

proc verify_world_stage(repo_dir: Path, packages: List[Package], fingerprint: Str) [fs, env, error] {
  let state = read_world_state(repo_dir)?
  let stored_fingerprint: Str = state.get("fingerprint")?

  if stored_fingerprint != fingerprint {
    return Err(PmError.PackageContract(f"${world_state_path(repo_dir).display()} belongs to a different world plan"))
  }

  let complete: Bool = state.get("complete")?

  if ! complete {
    return Err(PmError.PackageTarball("world staging repo is incomplete; run world-plan --build first"))
  }

  let built: List[Str] = state.get("built")?
  let proofed: List[Str] = state.get("proofed")?
  let unchanged: List[Str] = if state.has("unchanged") { state.get("unchanged")? } else { [] }
  let index_path = fp"${repo_dir}/index.json"

  if ! fs.exists(index_path)? {
    return Err(PmError.PackageTarball(f"${index_path.display()} is missing"))
  }

  let index = load_remote_index_from(index_path)?

  for entry in index {
    verify_staged_entry_tarball(repo_dir, entry)?
    verify_staged_entry_metadata(repo_dir, entry)?
  }

  for pkg in packages {
    let id = world_package_id(pkg)

    if ! built.contains(id) and ! unchanged.contains(id) {
      return Err(PmError.PackageTarball(f"${id} has not been built in the world stage"))
    }

    if ! proofed.contains(id) and ! unchanged.contains(id) {
      return Err(PmError.PackageTarball(f"${id} has not been proved in the world stage"))
    }
  }
}

proc load_local_packages(raw: List[Str]) [fs, env, error] -> Result[List[Package]] {
  let dirs = paths_from_args(raw)?
  load_package_dirs(dirs)?
}

proc command_smoke(ctx: PmContext, raw: List[Str]) [fs, net, process, env, time, error] {
  let built = build_local_packages(ctx, raw, false)?
  install_built_packages(ctx, built)?
  remove_built_packages(ctx, built)?
}

proc command_install(ctx: PmContext, raw: List[Str]) [fs, net, process, env, time, error] {
  if args_are_package_dirs(raw)? {
    build_and_install_local_packages(ctx, raw, true)?
  } else {
    install_remote_packages(ctx, raw)?
  }
}

proc command_search(ctx: PmContext, raw: List[Str]) [fs, env, error] {
  if raw.len() < 1 {
    return Err(usage("pm search ROOT WORK OUT QUERY [PKGDIR...]"))
  }

  let query = raw[0]
  var dirs: List[Path] = []
  var search_index = 1

  while search_index < raw.len() {
    dirs = dirs.push(fp"${raw[search_index]}")
    search_index += 1
  }

  let packages = load_package_dirs(dirs)?
  print_search_matches(ctx.root, query, packages)?
}

proc command_update(ctx: PmContext, raw: List[Str]) [fs, process, env, error] {
  let packages = load_local_packages(raw)?
  run_lifecycle_hooks("pre-update", "", ctx, "local")?
  write_local_index(ctx.out, packages)?
  run_lifecycle_hooks("post-update", "", ctx, "local")?
}

proc command_for_each_package(ctx: PmContext, raw: List[Str], action: Str) [fs, net, process, env, time, error] {
  let packages = load_local_packages(raw)?

  for pkg in packages {
    match action {
      "checksum" => print_package_checksums(ctx.work, pkg)?
      "update-checksums" => update_package_checksums(ctx.work, pkg)?
      "download" => download_package_sources(ctx.work, ctx.out, pkg)?
      "upload" => upload_package(ctx, pkg)?
      _ => return Err(PmError.Usage(f"unknown package action ${action}"))
    }
  }
}

proc stage_built_package(
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

proc command_upgrade(ctx: PmContext, raw: List[Str]) [fs, net, process, env, time, error] {
  let packages = load_local_packages(raw)?
  let upgrade_names = collect_upgrade_names(ctx.root, packages)?

  if upgrade_names.len() > 0 {
    let selected = filter_packages_by_names(packages, upgrade_names)?
    let ordered = order_packages(ctx.root, selected, true)?
    let built = build_packages(ctx, ordered)?
    install_built_packages(ctx, built)?
  }
}

proc local_package_names(packages: List[Package]) [] -> Map[Bool] {
  var names = {pkg.name: true for pkg in packages}
  names
}

proc missing_dependency_names(
  root: Path,
  packages: List[Package],
  include_mkdeps: Bool,
  local_names: Map[Bool],
) [fs, error] -> Result[List[Str]] {
  var names: List[Str] = []
  var seen: Map[Bool] = {}

  for pkg in packages {
    var deps = pkg.deps

    if include_mkdeps {
      deps = deps.extend(pkg.mkdeps)
      deps = deps.extend(pkg.target_build_deps)
    }

    for dep in deps {
      if ! local_names.get(dep, false) and ! seen.get(dep, false) and ! fs.exists(package_db_path(root, dep))? {
        names = names.push(dep)
        seen[dep] = true
      }
    }
  }

  names
}

proc install_remote_dependency_set(ctx: PmContext, names: List[Str]) [fs, net, process, env, time, error] {
  if names.len() > 0 {
    install_remote_packages(ctx, names)?
  }
}

proc install_remote_dependency_set_for_arch(
  ctx: PmContext,
  names: List[Str],
  arch: Str,
) [fs, net, process, env, time, error] {
  env {
    XSH_PM_ARCH = arch
    XSH_PM_TARGET_ARCH = arch
  } {
    install_remote_dependency_set(ctx, names)?
  } ?
}

proc install_chroot_base(
  ctx: PmContext,
  local_names: Map[Bool],
  include_tool_runtime: Bool,
) [fs, net, process, env, time, error] {
  if (env.get("XSH_PM_BUILD_CHROOT") ?? "1") == "0" {
    return
  }

  if ! local_names.get("baselayout", false) {
    install_remote_dependency_set(ctx, ["baselayout"])?
  }

  if ! local_names.get("laputa-pm", false) and ! local_names.get("xsh", false) {
    install_remote_dependency_set(ctx, ["laputa-pm"])?
  }

  if include_tool_runtime {
    install_remote_dependency_set(ctx, ["musl", "zlib", "llvm-toolchain"])?
  }
}

proc install_chroot_base_for_arch(
  ctx: PmContext,
  local_names: Map[Bool],
  include_tool_runtime: Bool,
  arch: Str,
) [fs, net, process, env, time, error] {
  env {
    XSH_PM_ARCH = arch
    XSH_PM_TARGET_ARCH = arch
  } {
    install_chroot_base(ctx, local_names, include_tool_runtime)?
  } ?
}

proc build_install_packages(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 6 {
    return Err(usage("pm build-install ROOT BUILD_ROOT WORK OUT PKGDIR..."))
  }

  let root = path.absolute(fp"${argv[1]}")?
  let build_root = path.absolute(fp"${argv[2]}")?
  let work = path.absolute(fp"${argv[3]}")?
  let out = path.absolute(fp"${argv[4]}")?
  var raw_args: List[Str] = []
  var build_i = 5

  while build_i < argv.len() {
    raw_args = raw_args.push(argv[build_i])
    build_i += 1
  }

  let packages = load_package_dirs(paths_from_args(raw_args)?)?
  let local_names = local_package_names(packages)
  let root_ctx: PmContext = {command: "build-install", root, work, out}
  let build_ctx: PmContext = {command: "build-install", root: build_root, work, out}
  fs.mkdir(work)?
  let lock = fs.lock(fp"${work}/pm.lock")?
  defer fs.unlock(lock)?
  fs.mkdir(root)?
  fs.mkdir(build_root)?
  fs.mkdir(out)?
  install_chroot_base(root_ctx, local_names, false)?
  install_chroot_base(build_ctx, local_names, true)?
  install_remote_dependency_set(root_ctx, missing_dependency_names(root, packages, false, local_names)?)?
  install_remote_dependency_set(build_ctx, missing_dependency_names(build_root, packages, true, local_names)?)?
  let ordered = order_packages(build_root, packages, true)?

  for pkg in ordered {
    var built: List[BuiltPackage] = []

    env {
      LAPUTA_ROOT = build_root.display()
      PATH = f"${build_root}/usr/bin:${env.get("PATH") ?? ""}"
    } {
      built = build_packages(build_ctx, [pkg])?
    } ?

    install_built_packages(root_ctx, built)?

    if root.display() != build_root.display() {
      install_built_packages(build_ctx, built)?
    }
  }
}

proc world_plan_repo(argv: List[Str]) [fs, net, process, env, time, error] {
  let opts: WorldPlanOptions = cli.parse(
    argv |> drop(1),
    {
      pkgdirs: {form: "...PKGDIR", repeated: true, required: true},
      arch: {form: "--arch ARCH", default: host_world_arch()?, help: "plan for ARCH (arm64 maps to aarch64)"},
      build: {form: "--build", default: false, help: "build all planned packages into the world staging repo"},
      upload: {form: "--upload", default: false, help: "upload only after the world staging repo is complete"},
      sync_rels: {
        form: "--sync-rels",
        default: false,
        help: "update PKGBUILD rels to exact planned rels present in remote",
      },
      to_tranche: {
        form: "--to-tranche N",
        default: -1,
        min: -1,
        help: "with --build, stop after tranche N and leave stage resumable",
      },
      jobs: {form: "-j --jobs N", kind: "Int", default: default_world_jobs()?, min: 1, help: "build jobs per tranche"},
    },
    "pm world-plan",
  )?

  let raw_args = opts.pkgdirs
  let build_requested = opts.build
  let upload_requested = opts.upload
  let sync_rels_requested = opts.sync_rels
  let world_jobs = opts.jobs
  let target_arch = validate_world_arch(opts.arch)?
  let to_tranche = parse_world_to_tranche(f"${opts.to_tranche}", "--to-tranche")?
  let host_arch = host_world_arch()?
  let world_build_arch = validate_world_arch(build_arch()?)?
  let native_cross_requested = (env.get("XSH_PM_NATIVE_CROSS") ?? "0") == "1"
  let cross_build = target_arch != world_build_arch

  if build_requested and target_arch != host_arch and ! native_cross_requested {
    return Err(PmError.Usage(f"world-plan --build for ${target_arch} is not supported on host ${host_arch}"))
  }

  if build_requested and cross_build and ! native_cross_requested {
    return Err(PmError.Usage("world-plan native cross build requires XSH_PM_NATIVE_CROSS=1"))
  }

  if build_requested and world_build_arch != host_arch {
    return Err(PmError.Usage(f"world-plan build arch ${world_build_arch} must match host ${host_arch}"))
  }

  let colors = color_enabled()
  print --flush ${ansi(colors, "1;34", "world-plan loading")} ${ansi(colors, "2", f"packages for ${target_arch}")}

  let package_dirs = expand_world_package_dirs(raw_args)?
  let pm_module_root = pm_module_root_path()?
  var packages: List[Package] = []

  env {
    XSH_PM_ARCH = target_arch
    XSH_PM_TARGET_ARCH = target_arch
    XSH_PM_BUILD_ARCH = world_build_arch
    XSH_MODULE_PATH = f"${pm_module_root.display()}:${env.get("XSH_MODULE_PATH") ?? ""}"
  } {
    packages = load_package_dirs(package_dirs)?
  } ?

  let fingerprint = world_plan_content_hash(packages, target_arch)?
  let cache_key = world_plan_cache_key(packages, target_arch)
  let repo_dir = world_cache_repo_dir(cache_key)?
  let root = fp"${repo_dir}/.world/root"
  let build_root = if cross_build { fp"${repo_dir}/.world/build-root" } else { root }
  let work = fp"${repo_dir}/.work"
  let out = fp"${repo_dir}/.out"
  let root_ctx: PmContext = {command: "world-plan", root, work, out}
  let build_ctx: PmContext = {command: "world-plan", root: build_root, work, out}
  let upload_ctx: PmContext = {...build_ctx, command: "upload"}
  fs.mkdir(repo_dir)?
  fs.mkdir(root)?
  if build_root.display() != root.display() {
    fs.mkdir(build_root)?
  }
  fs.mkdir(work)?
  fs.mkdir(out)?
  let lock = fs.lock(fp"${work}/pm.lock")?
  defer fs.unlock(lock)?
  let index_path = fp"${repo_dir}/index.json"
  var index: List[RemotePackage] = []

  if fs.exists(index_path)? {
    index = load_remote_index_from(index_path)?
  }

  print --flush f"${ansi(colors, "1;36", "world-repo")} ${ansi(colors, "2", repo_dir.display())}"
  print --flush ${ansi(colors, "1;34", "world-plan fetching")} ${ansi(colors, "2", "remote index")}

  let repo_urls = load_repo_urls()?
  var remote_index: List[RemotePackage] = []
  var remote_latest: Map[RemotePackage] = {}
  var build_remote_latest: Map[RemotePackage] = {}

  if repo_urls.repo != "" {
    remote_index = load_remote_index_from_repo(repo_urls.repo, out)?
    remote_latest = world_latest_remote_map(remote_index, target_arch)?
    build_remote_latest = world_latest_remote_map(remote_index, world_build_arch)?

    if build_requested {
      validate_world_remote_versions_for_plan(packages, remote_latest, true)?
    }
  }

  let local_names = local_package_names(packages)
  let ordered = order_world_build_packages(build_root, packages, index, target_arch, ! cross_build)?
  let state_planned_rels = world_state_planned_rels(repo_dir, packages)?
  let planned = planned_world_packages(ordered, local_names, remote_latest, state_planned_rels)?
  let planned_by_name = planned_world_package_map(planned)
  print_world_plan(ordered, planned, local_names, world_jobs, remote_latest, target_arch)?

  if build_requested {
    let state = ensure_world_state_compatible(repo_dir, fingerprint, planned)?
    let recorded_built: List[Str] = state.get("built")?
    let recorded_proofed: List[Str] = state.get("proofed")?
    let recorded_unchanged: List[Str] = if state.has("unchanged") { state.get("unchanged")? } else { [] }

    if recorded_built.len() == 0 and recorded_unchanged.len() == 0 {
      fs.remove(root, missing_ok: true)?
      if build_root.display() != root.display() {
        fs.remove(build_root, missing_ok: true)?
      }
      fs.mkdir(root)?
      if build_root.display() != root.display() {
        fs.mkdir(build_root)?
      }
    }

    var built_names: Map[Bool] = {}
    var unchanged_names: Map[Bool] = {}
    let levels = world_plan_levels(ordered, local_names)
    let max_level = world_plan_max_level(ordered, levels)
    let build_max_level = if to_tranche >= 0 and to_tranche < max_level { to_tranche } else { max_level }
    let build_local_names: Map[Bool] = if cross_build { map.empty() } else { local_names }
    print --flush ${ansi(colors, "1;34", "world-build preparing")} ${ansi(colors, "2", "chroot base")}
    install_chroot_base_for_arch(root_ctx, local_names, false, target_arch)?
    if build_root.display() != root.display() {
      install_chroot_base_for_arch(build_ctx, build_local_names, false, world_build_arch)?
    }
    var level = 0

    while level <= build_max_level {
      let tranche = world_packages_at_level(ordered, levels, level)
      var pending: List[Package] = []
      var pending_originals: List[Package] = []

      for pkg in tranche {
        let build_pkg: Package = planned_by_name.get(pkg.name)?
        let id = world_package_id(build_pkg)

        if recorded_unchanged.contains(id) and world_stage_package_present_in_roots(
          root,
          build_root,
          pkg.name,
          cross_build,
        )? {
          built_names[pkg.name] = true
          unchanged_names[pkg.name] = true
          print --flush ${pkg.name} $id "stage:" "unchanged"
        } else if recorded_built.contains(id) and recorded_proofed.contains(id) and world_stage_package_present_in_roots(
          root,
          build_root,
          pkg.name,
          cross_build,
        )? {
          built_names[pkg.name] = true
          print --flush ${pkg.name} $id "stage:" "cached"
        } else {
          var build_dependency_names = effective_world_build_dependencies(pkg, cross_build)

          if world_dependency_is_seeded(pkg, "zlib", cross_build) and ! build_dependency_names.contains("zlib") {
            build_dependency_names = build_dependency_names.push("zlib")
          }

          let root_dependency_names = if cross_build {
            effective_world_target_dependencies(pkg, cross_build)
          } else {
            build_dependency_names
          }

          let missing_root_dependencies = if cross_build {
            missing_world_dependencies(root, root_dependency_names, local_names, built_names)?
          } else {
            missing_world_build_dependencies(root, pkg, root_dependency_names, local_names, built_names, cross_build)?
          }

          install_remote_dependency_set_for_arch(root_ctx, missing_root_dependencies, target_arch)?

          let missing_build_dependencies = if cross_build {
            missing_fresh_world_dependencies(
              build_root,
              build_dependency_names,
              build_local_names,
              built_names,
              build_remote_latest,
            )?
          } else {
            missing_world_build_dependencies(
              build_root,
              pkg,
              build_dependency_names,
              build_local_names,
              built_names,
              cross_build,
            )?
          }

          install_remote_dependency_set_for_arch(build_ctx, missing_build_dependencies, world_build_arch)?
          pending = pending.push(build_pkg)
          pending_originals = pending_originals.push(pkg)
        }
      }

      if pending.len() > 0 {
        print --flush f"${ansi(colors, "1;34", f"world-build tranche ${level}")} ${package_count_text(pending.len())} ${ansi(
          colors,
          "2",
          f"jobs ${world_jobs}",
        )}"

        var built_batches: List[List[BuiltPackage]] = []

        if world_jobs == 1 {
          for pkg in pending {
            built_batches = built_batches.push(
              build_world_package(build_ctx, root, build_root, pkg, target_arch, world_build_arch, cross_build)?,
            )
          }
        } else {
          built_batches = pending
            |> par-map --jobs=world_jobs { |pkg|
              build_world_package(build_ctx, root, build_root, pkg, target_arch, world_build_arch, cross_build)
            }
        }

        let remote_hashes = world_remote_metadata_hashes(
          repo_urls.repo,
          out,
          pending_originals,
          remote_latest,
          world_jobs,
        )?

        var pending_index = 0
        var tranche_errors: List[Str] = []

        for built in built_batches {
          let original_pkg = pending_originals[pending_index]
          let build_pkg = pending[pending_index]

          if built.len() == 0 {
            let pkg_id = world_package_id(build_pkg)
            let msg = f"${original_pkg.name} ${pkg_id}"
            tranche_errors.push(msg)
            eprint f"world-build: ${msg} failed"
          } else {
            var unchanged = false

            if world_package_id(build_pkg) == world_package_id(original_pkg) and repo_urls.repo != "" and remote_latest.has(
              original_pkg.name,
            ) {
              let rpkg: RemotePackage = remote_latest.get(original_pkg.name)?

              if compare_version_text(original_pkg.ver, rpkg.ver) == 0 and compare_version_text(
                original_pkg.rel,
                rpkg.rel,
              ) <= 0 {
                let remote_hash = remote_hashes.get(original_pkg.name, "")

                if remote_hash != "" and remote_hash == built[0].metadata_sha256 {
                  install_remote_dependency_set_for_arch(root_ctx, [original_pkg.name], target_arch)?

                  if ! cross_build and root.display() != build_root.display() {
                    install_remote_dependency_set_for_arch(build_ctx, [original_pkg.name], world_build_arch)?
                  }

                  built_names[original_pkg.name] = true
                  unchanged_names[original_pkg.name] = true
                  unchanged = true
                  print --flush ${original_pkg.name} world_package_id(original_pkg) "stage:" "unchanged" "metadata"
                }
              }
            }

            if ! unchanged {
              for item in built {
                index = stage_built_package(repo_dir, upload_ctx, index, item)?
              }

              json.write(index_path, index)?
              remove_world_unowned_install_conflicts(root, built)?
              install_world_built_packages(root_ctx, built)?

              if ! cross_build and root.display() != build_root.display() {
                remove_world_unowned_install_conflicts(build_root, built)?
                install_world_built_packages(build_ctx, built)?
              }

              built_names[original_pkg.name] = true
            }

            write_world_state(repo_dir, fingerprint, planned, built_names, unchanged_names, false)?
          }

          pending_index += 1
        }

        if tranche_errors.len() > 0 {
          eprint f"tranche ${level}: ${tranche_errors.len()}/${pending.len()} failed:"

          for error in tranche_errors {
            eprint f"  ${error}"
          }

          return Err(
            PmError.Usage(f"tranche ${level} had ${tranche_errors.len()} failure(s); state saved for successes"),
          )
        }
      }

      level += 1
    }

    if build_max_level >= max_level {
      write_world_state(repo_dir, fingerprint, planned, built_names, unchanged_names, true)?
      print --flush "world-plan" build complete
    } else {
      write_world_state(repo_dir, fingerprint, planned, built_names, unchanged_names, false)?
      print --flush f"world-plan build paused at tranche ${build_max_level}"
    }
  }

  if upload_requested {
    verify_world_stage(repo_dir, planned, fingerprint)?
    upload_repo_export(["upload-repo-export", repo_dir.display()])?

    if sync_rels_requested and repo_urls.repo != "" {
      remote_index = load_remote_index_from_repo(repo_urls.repo, out)?
      remote_latest = world_latest_remote_map(remote_index, target_arch)?
    }
  }

  if sync_rels_requested {
    sync_world_rels(ordered, planned_by_name, remote_latest)?
  }
}

proc build_set_repo(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 3 {
    return Err(usage("pm build-set REPO_DIR PKGDIR..."))
  }

  let repo_dir = path.absolute(fp"${argv[1]}")?
  let root = fp"${repo_dir}/.set-root"
  let build_root = fp"${repo_dir}/.set-build-root"
  let work = fp"${repo_dir}/.work"
  let out = fp"${repo_dir}/.out"
  let root_ctx: PmContext = {command: "build-set", root, work, out}
  let build_ctx: PmContext = {command: "build-set", root: build_root, work, out}
  let upload_ctx: PmContext = {...build_ctx, command: "upload"}
  var raw_args: List[Str] = []
  var build_i = 2

  while build_i < argv.len() {
    raw_args = raw_args.push(argv[build_i])
    build_i += 1
  }

  fs.mkdir(repo_dir)?
  fs.remove(root, missing_ok: true)?
  fs.remove(build_root, missing_ok: true)?
  fs.mkdir(root)?
  fs.mkdir(build_root)?
  fs.mkdir(work)?
  fs.mkdir(out)?
  fs.remove(remote_index_cache_path(out), missing_ok: true)?
  let lock = fs.lock(fp"${work}/pm.lock")?
  defer fs.unlock(lock)?
  let index_path = fp"${repo_dir}/index.json"
  var index: List[RemotePackage] = []

  if fs.exists(index_path)? {
    index = load_remote_index_from(index_path)?
  }

  let packages = load_local_packages(raw_args)?
  let local_names = local_package_names(packages)
  let ordered = packages
  let built_names: Map[Bool] = {}

  for pkg in ordered {
    fs.remove(root, missing_ok: true)?
    fs.remove(build_root, missing_ok: true)?
    fs.mkdir(root)?
    fs.mkdir(build_root)?
    install_chroot_base(root_ctx, local_names, false)?
    install_chroot_base(build_ctx, local_names, true)?

    install_remote_dependency_set(
      root_ctx,
      missing_world_dependencies(root, effective_world_dependencies(pkg, false), local_names, built_names)?,
    )?

    install_remote_dependency_set(
      build_ctx,
      missing_world_dependencies(build_root, effective_world_dependencies(pkg, true), local_names, built_names)?,
    )?

    var built: List[BuiltPackage] = []

    env {
      LAPUTA_ROOT = build_root.display()
      PATH = f"${build_root}/usr/bin:${env.get("PATH") ?? ""}"
    } {
      built = build_packages(build_ctx, [pkg])?
    } ?

    for item in built {
      index = stage_built_package(repo_dir, upload_ctx, index, item)?
    }

    json.write(index_path, index)?
  }
}

proc build_prepared_package_command(argv: List[Str]) [fs, process, env, error] {
  if argv.len() != 5 {
    return Err(usage("pm build-prepared-package PKGDIR SRC DEST TARBALL"))
  }

  build_prepared_package(
    path.absolute(fp"${argv[1]}")?,
    path.absolute(fp"${argv[2]}")?,
    path.absolute(fp"${argv[3]}")?,
    path.absolute(fp"${argv[4]}")?,
  )?
}

proc upload_set_repo(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 3 {
    return Err(usage("pm upload-set REPO_DIR PKGDIR..."))
  }

  let repo_dir = path.absolute(fp"${argv[1]}")?
  let build_root = fp"${repo_dir}/.set-build-root"
  let work = fp"${repo_dir}/.work"
  let out = fp"${repo_dir}/.out"
  let upload_ctx: PmContext = {command: "upload", root: build_root, work, out}
  var raw_args: List[Str] = []
  var build_i = 2

  while build_i < argv.len() {
    raw_args = raw_args.push(argv[build_i])
    build_i += 1
  }

  fs.mkdir(work)?
  fs.mkdir(out)?
  let lock = fs.lock(fp"${work}/pm.lock")?
  defer fs.unlock(lock)?
  let packages = load_local_packages(raw_args)?

  for pkg in packages {
    upload_package(upload_ctx, pkg)?
  }
}

proc build_upload_set_repo(argv: List[Str]) [fs, net, process, env, time, error] {
  build_set_repo(argv)?
  upload_set_repo(argv)?
}

proc upload_repo_export_file(repo: Str, rel: Path, source: Path, token: Str, work: Path) [fs, net, time, error] {
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

proc upload_repo_export(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 2 {
    return Err(usage("pm upload-repo-export REPO_DIR"))
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

pure supports_repo_default_context(command: Str) -> Bool {
  [
    "install",
    "remove",
    "list",
    "info",
    "tree",
    "search",
    "outdated",
    "update",
    "upgrade",
    "checksum",
    "update-checksums",
    "download",
    "refresh-index",
    "auth",
    "upload",
    "help-ext",
  ].contains(command)
}

pure command_requires_package_dirs(command: Str) -> Bool {
  ["outdated", "update", "upgrade", "checksum", "update-checksums", "download", "upload"].contains(command)
}

pure arg_looks_like_path(value: Str) -> Bool {
  value.starts_with("/") or value.starts_with(".") or value.contains("/")
}

pure explicit_context_is_likely(argv: List[Str]) -> Bool {
  argv.len() >= 4 and (arg_looks_like_path(argv[1]) or arg_looks_like_path(argv[2]) or arg_looks_like_path(argv[3]))
}

proc all_args_are_package_dirs(argv: List[Str], start: Int) [fs, error] -> Result[Bool] {
  if argv.len() <= start {
    return false
  }

  var i = start

  while i < argv.len() {
    let dir = fp"${argv[i]}"

    if ! fs.exists(fp"${dir}/PKGBUILD.xsh")? {
      return false
    }

    i += 1
  }

  true
}

proc current_pm_repo_root() [fs, error] -> Result[Path] {
  var dir = fs.cwd()?

  while true {
    if fs.exists(fp"${dir}/pm.xsh")? and fs.exists(fp"${dir}/pm")? {
      return dir
    }

    let parent = dir.parent

    if parent.display() == dir.display() {
      return p""
    }

    dir = parent
  }

  p""
}

proc default_root_command_argv(argv: List[Str]) [fs, error] -> Result[List[Str]] {
  if ! supports_repo_default_context(argv[0]) {
    return argv
  }

  let args_are_pkgdirs = all_args_are_package_dirs(argv, 1)?

  if ! args_are_pkgdirs and command_requires_package_dirs(argv[0]) {
    return argv
  }

  if ! args_are_pkgdirs and explicit_context_is_likely(argv) {
    return argv
  }

  let repo_root = current_pm_repo_root()?

  if repo_root.display() == "" {
    return argv
  }

  var expanded: List[Str] = [
    argv[0],
    fp"${repo_root}/.root".display(),
    fp"${repo_root}/.work".display(),
    fp"${repo_root}/.out".display(),
  ]

  var i = 1

  while i < argv.len() {
    expanded = expanded.push(argv[i])
    i += 1
  }

  expanded
}

proc handle_cli_command(parsed: Cli) [fs, net, process, env, time, error] {
  let command = parsed.command
  let ctx: PmContext = {command, root: parsed.root, work: parsed.work, out: parsed.out}
  fs.mkdir(ctx.work)?
  let lock = fs.lock(fp"${ctx.work}/pm.lock")?
  defer fs.unlock(lock)?
  fs.mkdir(ctx.root)?
  fs.mkdir(ctx.out)?

  match command {
    "smoke" => command_smoke(ctx, parsed.raw)?
    "install" => command_install(ctx, parsed.raw)?
    "remove" => remove_installed_packages(ctx, parsed.raw)?
    "list" => print_installed_list(ctx.root)?
    "info" => {
      for name in parsed.raw {
        print_package_info(ctx.root, name)?
      }
    }
    "tree" => print_dependency_tree(ctx.root, parsed.raw)?
    "search" => command_search(ctx, parsed.raw)?
    "outdated" => print_outdated(ctx.root, load_local_packages(parsed.raw)?)?
    "update" => command_update(ctx, parsed.raw)?
    "checksum" => command_for_each_package(ctx, parsed.raw, command)?
    "update-checksums" => command_for_each_package(ctx, parsed.raw, command)?
    "download" => command_for_each_package(ctx, parsed.raw, command)?
    "refresh-index" => {
      run_lifecycle_hooks("pre-update", "", ctx, "remote")?
      let _ = refresh_remote_index(ctx.out)?
      run_lifecycle_hooks("post-update", "", ctx, "remote")?
    }
    "auth" => store_auth_token(ctx.root, parsed.raw)?
    "upload" => command_for_each_package(ctx, parsed.raw, command)?
    "upgrade" => command_upgrade(ctx, parsed.raw)?
    "help-ext" => print_extension_help()?
    _ => invoke_extension(command, ctx, parsed.raw)?
  }
}

proc build_repo(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 3 {
    return Err(usage("pm build REPO_DIR PKGDIR..."))
  }

  let repo_dir = path.absolute(fp"${argv[1]}")?
  let build_work = fp"${repo_dir}/.work"
  let build_out = fp"${repo_dir}/.out"
  let build_root = fp"${repo_dir}/.root"
  let ctx: PmContext = {command: "build", root: build_root, work: build_work, out: build_out}
  let upload_ctx: PmContext = {...ctx, command: "upload"}
  fs.mkdir(repo_dir)?
  var raw_args: List[Str] = []
  var build_i = 2

  while build_i < argv.len() {
    raw_args = raw_args.push(argv[build_i])
    build_i += 1
  }

  let index_path = fp"${repo_dir}/index.json"
  var index: List[RemotePackage] = []

  if fs.exists(index_path)? {
    index = load_remote_index_from(index_path)?
  }

  let packages = load_local_packages(raw_args)?
  let local_names = local_package_names(packages)
  install_remote_dependency_set(ctx, missing_dependency_names(build_root, packages, true, local_names)?)?
  let ordered = order_repo_build_packages(build_root, packages, index)?
  let built = build_packages(ctx, ordered)?

  for item in built {
    index = stage_built_package(repo_dir, upload_ctx, index, item)?
  }

  json.write(index_path, index)?
}

proc main(...argv: List[Str]) [fs, net, process, env, time, error] {
  var a = argv

  if a.len() >= 1 and a[0] == "--" {
    var shifted: List[Str] = []
    var i = 1

    while i < a.len() {
      shifted = shifted.push(a[i])
      i += 1
    }

    a = shifted
  }

  if a.len() == 0 or a[0] == "-h" or a[0] == "--help" or a[0] == "help" {
    print_help()
    return
  }

  if a.len() >= 1 and a[0] == "build" {
    build_repo(a)?
    return
  }

  if a.len() >= 1 and a[0] == "build-install" {
    build_install_packages(a)?
    return
  }

  if a.len() >= 1 and a[0] == "world-plan" {
    world_plan_repo(a)?
    return
  }

  if a.len() >= 1 and a[0] == "build-set" {
    build_set_repo(a)?
    return
  }

  if a.len() >= 1 and a[0] == "build-prepared-package" {
    build_prepared_package_command(a)?
    return
  }

  if a.len() >= 1 and a[0] == "upload-set" {
    upload_set_repo(a)?
    return
  }

  if a.len() >= 1 and a[0] == "build-upload-set" {
    build_upload_set_repo(a)?
    return
  }

  if a.len() >= 1 and a[0] == "upload-repo-export" {
    upload_repo_export(a)?
    return
  }

  handle_cli_command(parse_pm_cli(default_root_command_argv(a)?)?)?
}
