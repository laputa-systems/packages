##! PM world operations and shared package-manager policy.
use build as pm_build
use buildroot
use catalog
use elfdeps
use graph
use install
use local
use policy
use remote
use repo
use types
use util

type WorldPlanOptions = {
  pkgdirs: List[Str],
  arch: Str,
  build: Bool,
  upload: Bool,
  to_tranche: Int,
  jobs: Int,
}

type WorldPlanResult = {packages: List[types.Package], reasons: Map[Str]}

pure world_build_policy(cross_build: Bool) -> types.BuildPolicy {
  policy.with_native_build(policy.aarch64_docker(), ! cross_build)
}

pure world_dependency_is_seeded(pkg: types.Package, dep: Str, cross_build: Bool) -> Bool {
  policy.is_bootstrap_dependency(world_build_policy(cross_build), pkg.name, dep)
}

proc order_world_build_packages(
  root: Path,
  packages: List[types.Package],
  index: List[types.RemotePackage],
  arch: Str,
  include_mkdeps_host: Bool,
) [fs, env, error] -> Result[List[types.Package]] {
  var local_names: Map[Bool] = {}
  let remote_names = remote.selected_snapshot_names(index, arch)
  var available_names = remote_names

  for pkg in packages {
    local_names[pkg.name] = true
  }

  for pkg in packages {
    for dependency in pkg.deps.extend(pkg.mkdeps_host).extend(pkg.mkdeps_target) {
      if ! local_names.get(dependency, false) {
        available_names = available_names.push(dependency)
      }
    }
  }

  let local_catalog = catalog.from_packages(root, packages, available_names)?
  let value = remote.catalog_with_selected_snapshot(local_catalog, index, arch)?
  let cross_build = ! include_mkdeps_host
  let edges = graph.edges(value, world_build_policy(cross_build))?
  var ordering_kinds = [types.Runtime, types.BuildTarget, types.Bootstrap]

  if include_mkdeps_host {
    ordering_kinds = ordering_kinds.push(types.BuildHost)
  }

  for edge in edges {
    if edge.kind in ordering_kinds and ! local_names.get(edge.to, false) and edge.kind != types.Bootstrap and edge.to not in remote_names and ! fs.exists(
      util.package_db_path(root, edge.to),
    )? {
      return Err(types.PmError.MissingDependency(f"${edge.from} depends on missing ${edge.to}"))
    }
  }

  let levels = graph.topological_levels(catalog.package_names(value), [edge for edge in edges if edge.kind in ordering_kinds])?
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

## Exported PM declaration `missing_world_dependencies`.
export proc missing_world_dependencies(
  root: Path,
  deps: List[Str],
  local_names: Map[Bool],
  built_names: Map[Bool],
) [fs, error] -> Result[List[Str]] {
  var missing = []
  var seen: Map[Bool] = {}

  for dep in deps {
    if local_names.get(dep, false) and ! built_names.get(dep, false) {
      return Err(types.PmError.MissingDependency(f"${dep} has not been built yet"))
    }

    if ! seen.get(dep, false) and ! fs.exists(util.package_db_path(root, dep))? {
      missing = missing.push(dep)
      seen[dep] = true
    }
  }

  missing
}

proc missing_world_build_dependencies(
  root: Path,
  pkg: types.Package,
  deps: List[Str],
  local_names: Map[Bool],
  built_names: Map[Bool],
  cross_build: Bool,
) [fs, error] -> Result[List[Str]] {
  var missing = []
  var seen: Map[Bool] = {}

  for dep in deps {
    if local_names.get(dep, false) and ! built_names.get(dep, false) and ! world_dependency_is_seeded(
      pkg,
      dep,
      cross_build,
    ) {
      return Err(types.PmError.MissingDependency(f"${dep} has not been built yet"))
    }

    if ! seen.get(dep, false) and ! fs.exists(util.package_db_path(root, dep))? {
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
  remote_latest: Map[types.RemotePackage],
) [fs, error] -> Result[List[Str]] {
  var missing = []
  var seen: Map[Bool] = {}

  for dep in deps {
    if local_names.get(dep, false) and ! built_names.get(dep, false) {
      return Err(types.PmError.MissingDependency(f"${dep} has not been built yet"))
    }

    if ! seen.get(dep, false) {
      let db = util.package_db_path(root, dep)
      var needs_install = ! fs.exists(db)?

      if ! needs_install and remote_latest.has(dep) {
        let remote_pkg: types.RemotePackage = remote_latest.get(dep)?
        let metadata = local.load_metadata(db)?
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

# Temporary: xsh 0.0.0 is a development marker that should be considered
# newer than any release-* version in the remote index.
pure world_package_always_newer_than_remote(name: Str, ver: Str) -> Bool {
  name == "xsh" and ver == "0.0.0"
}

proc effective_world_target_dependencies(pkg: types.Package, include_mkdeps_target: Bool) [] -> List[Str] {
  var deps = pkg.deps

  if include_mkdeps_target {
    deps = deps.extend(pkg.mkdeps_target)
  }

  deps
}

## Exported PM declaration `effective_world_dependencies`.
export proc effective_world_dependencies(pkg: types.Package, include_mkdeps_host: Bool) [] -> List[Str] {
  var deps = effective_world_target_dependencies(pkg, include_mkdeps_host)

  if include_mkdeps_host {
    deps = deps.extend(pkg.mkdeps_host)
  }

  deps
}

proc effective_world_build_dependencies(pkg: types.Package, cross_build: Bool) [] -> List[Str] {
  var deps = []

  if cross_build {
    deps = pkg.mkdeps_host
  } else {
    deps = effective_world_dependencies(pkg, true)
  }

  deps
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
  let source_db = util.package_db_path(source_root, name)
  let dest_db = util.package_db_path(dest_root, name)
  let manifest = local.load_manifest(source_db)?
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
  var names = ["baselayout", "xsh", "zlib"]
  var required = [false, false, false]

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
      let db = util.package_db_path(staged_root, name)

      if fs.exists(db)? {
        copy_world_seed_package(staged_root, package_root, name)?
        copied[name] = true
        let metadata = local.load_metadata(db)?
        let package_deps: List[Str] = metadata.get("deps")?

        for dep in package_deps {
          if ! copied.get(dep, false) {
            names = names.push(dep)
            required = required.push(is_required)
          }
        }
      } else if is_required {
        return Err(types.PmError.MissingDependency(f"${owner} requires staged ${name}"))
      }
    }

    index += 1
  }

  if ! fs.exists(fp"${package_root}/lib")? and fs.exists(fp"${package_root}/usr/lib")? {
    fs.symlink(p"usr/lib", fp"${package_root}/lib")?
  }
}

proc effective_world_seed_dependencies(
  pkg: types.Package,
  include_mkdeps_host: Bool,
  include_mkdeps_target: Bool,
) [] -> List[Str] {
  var deps = effective_world_target_dependencies(pkg, include_mkdeps_target)

  if include_mkdeps_host {
    deps = deps.extend(pkg.mkdeps_host)
  }

  deps
}

proc seed_world_package_root(
  staged_root: Path,
  package_root: Path,
  pkg: types.Package,
  include_mkdeps_host: Bool,
  include_mkdeps_target: Bool,
) [fs, error] {
  seed_world_package_dependency_set(
    staged_root,
    package_root,
    pkg.name,
    effective_world_seed_dependencies(pkg, include_mkdeps_host, include_mkdeps_target),
  )?
}

pure world_state_path(repo_dir: Path) -> Path {
  fp"${repo_dir}/.world/state.json"
}

pure world_package_id(pkg: types.Package) -> Str {
  util.package_id(pkg.name, pkg.ver, pkg.rel)
}

proc world_package_rows(packages: List[types.Package]) [] -> List[Record] {
  var rows = []

  for pkg in packages {
    let sources = [source.source.display() for source in pkg.upstream_sources]

    let upstream_sources = [
      {
        source: source.source.display(),
        kind: source.kind,
        architectures: source.architectures,
        checksums: source.checksums,
      }
      for source in pkg.upstream_sources
    ]

    rows = rows.push({
      name: pkg.name,
      ver: pkg.ver,
      rel: pkg.rel,
      id: world_package_id(pkg),
      dir: pkg.dir.display(),
      deps: pkg.deps,
      mkdeps_host: pkg.mkdeps_host,
      mkdeps_target: pkg.mkdeps_target,
      sources,
      upstream_sources,
    })
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

  return Err(types.PmError.PackageContract("cannot find PM module root"))
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

proc world_plan_content_hash(packages: List[types.Package], arch: Str) [fs, error] -> Result[Str] {
  var body = f"""arch	${arch}
"""

  let sorted = packages |> sort-by .name

  for pkg in sorted {
    body = append_fingerprint_file(body, f"pkg/${pkg.name}/PKGBUILD.xsh", fp"${pkg.dir}/PKGBUILD.xsh")?
  }

  bytes.from_text(body).sha256().hex()
}

proc world_plan_cache_key(packages: List[types.Package], arch: Str) [] -> Str {
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
    return Err(types.PmError.PackageContract("HOME is required for world-plan cache"))
  }

  fp"${home}/.cache/laputa/world-${cache_key}"
}

proc expand_world_package_dirs(raw: List[Str]) [fs, error] -> Result[List[Path]] {
  var dirs = []
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
      var children = [
        child.path
        for child in fs.children(input)?
        if child.kind == "dir" and fs.exists(
          fp"${child.path}/PKGBUILD.xsh",
        )?
      ]

      children = children |> sort-by .display()

      if children.len() == 0 {
        return Err(types.PmError.PackageContract(f"${input.display()} is not a package dir or package root"))
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

proc world_local_dependency_names(pkg: types.Package, local_names: Map[Bool]) [] -> List[Str] {
  var names = []
  var seen: Map[Bool] = {}

  for dep in effective_world_dependencies(pkg, true) {
    if local_names.get(dep, false) and ! seen.get(dep, false) and ! world_dependency_is_seeded(pkg, dep, false) {
      names = names.push(dep)
      seen[dep] = true
    }
  }

  names
}

proc world_dependency_kind(pkg: types.Package, dep: Str) [] -> Str {
  if dep in pkg.deps {
    return "runtime"
  }

  if dep in pkg.mkdeps_target {
    return "target-build"
  }

  if dep in pkg.mkdeps_host {
    return "build-host"
  }

  "world/tool"
}

proc summarize_changed_dependencies(changed_deps: List[Str]) [] -> Str {
  if changed_deps.len() <= 4 {
    return changed_deps.join(", ")
  }

  var head = []
  var index = 0

  while index < 4 {
    head = head.push(changed_deps[index])
    index += 1
  }

  f"${head.join(", ")}, +${changed_deps.len() - 4} more"
}

proc world_plan_levels(ordered: List[types.Package], cross_build: Bool) [error] -> Result[Map[Int]] {
  var available_names: List[Str] = []

  for pkg in ordered {
    available_names = available_names.extend(pkg.deps).extend(pkg.mkdeps_host).extend(pkg.mkdeps_target)
  }

  let value = catalog.from_packages(p".", ordered, available_names)?
  let edges = graph.edges(value, world_build_policy(cross_build))?
  let graph_levels = graph.topological_levels(catalog.package_names(value), edges)?
  var levels: Map[Int] = {}
  var level = 0

  for names in graph_levels {
    for name in names {
      levels[name] = level
    }

    level += 1
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

proc world_plan_max_level(ordered: List[types.Package], levels: Map[Int]) [] -> Int {
  var max_level = 0

  for pkg in ordered {
    let level = levels.get(pkg.name, 0)

    if level > max_level {
      max_level = level
    }
  }

  max_level
}

proc world_packages_at_level(ordered: List[types.Package], levels: Map[Int], level: Int) [] -> List[types.Package] {
  var tranche = [pkg for pkg in ordered if levels.get(pkg.name, 0) == level]
  tranche
}

proc validate_world_arch(arch: Str) [error] -> Result[Str] {
  let normalized = util.normalize_arch(arch)

  if normalized == "aarch64" or normalized == "x86_64" {
    return normalized
  }

  return Err(types.PmError.Usage(f"unsupported world-plan arch ${arch}; expected aarch64 or x86_64"))
}

proc host_world_arch() [env, error] -> Result[Str] {
  let os = system.uname()?
  validate_world_arch(os.machine)
}

proc world_plan_remote_annotation(
  pkg: types.Package,
  planned: types.Package,
  remote_latest: Map[types.RemotePackage],
) [error] -> Result[Str] {
  if ! remote_latest.has(pkg.name) {
    return ""
  }

  if world_package_always_newer_than_remote(pkg.name, pkg.ver) {
    return ""
  }

  let remote_pkg: types.RemotePackage = remote_latest.get(pkg.name)?
  let cmp = compare_version_release(planned.ver, planned.rel, remote_pkg.ver, remote_pkg.rel)

  if cmp >= 0 {
    return ""
  }

  f"remote newer ${util.version_id(remote_pkg.ver, remote_pkg.rel)}"
}

proc planned_world_packages(
  ordered: List[types.Package],
  local_names: Map[Bool],
  remote_latest: Map[types.RemotePackage],
) [error] -> Result[WorldPlanResult] {
  var planned = []
  var changed: Map[Bool] = {}
  var reasons: Map[Str] = {}

  for pkg in ordered {
    var planned_pkg = pkg
    var changed_dep = false
    var changed_deps = []

    for dep in world_local_dependency_names(pkg, local_names) {
      if changed.get(dep, false) {
        changed_dep = true
        changed_deps = changed_deps.push(f"${world_dependency_kind(pkg, dep)} dependency ${dep}")
      }
    }

    if remote_latest.has(pkg.name) {
      let remote_pkg: types.RemotePackage = remote_latest.get(pkg.name)?

      if compare_version_text(pkg.ver, remote_pkg.ver) == 0 {
        if compare_version_text(pkg.rel, remote_pkg.rel) > 0 {
          reasons[pkg.name] = f"local rel above remote ${util.version_id(remote_pkg.ver, remote_pkg.rel)}"
        }
      } else {
        reasons[pkg.name] = f"version differs from remote ${util.version_id(remote_pkg.ver, remote_pkg.rel)}"
      }

      changed[pkg.name] = compare_version_release(planned_pkg.ver, planned_pkg.rel, remote_pkg.ver, remote_pkg.rel) != 0

      if changed_dep and compare_version_release(pkg.ver, pkg.rel, remote_pkg.ver, remote_pkg.rel) <= 0 {
        return Err(
          types.PmError.PackageContract(
            f"${pkg.name} dependencies changed (${summarize_changed_dependencies(changed_deps)}); bump its declared rel above ${util.version_id(
              remote_pkg.ver,
              remote_pkg.rel,
            )}",
          ),
        )
      }
    } else {
      reasons[pkg.name] = "new package"
      changed[pkg.name] = true
    }

    if changed_dep and ! reasons.has(pkg.name) {
      reasons[pkg.name] = f"changed ${summarize_changed_dependencies(changed_deps)}"
    }

    planned = planned.push(planned_pkg)
  }

  {packages: planned, reasons}
}

proc planned_world_package_map(planned: List[types.Package]) [] -> Map[types.Package] {
  var packages = {pkg.name: pkg for pkg in planned}
  packages
}

proc world_plan_version_text(
  pkg: types.Package,
  planned: types.Package,
  remote_latest: Map[types.RemotePackage],
  colors: Bool,
) [error] -> Result[Str] {
  if remote_latest.has(pkg.name) {
    let remote_pkg: types.RemotePackage = remote_latest.get(pkg.name)?

    if compare_version_text(pkg.ver, remote_pkg.ver) == 0 and compare_version_text(pkg.rel, remote_pkg.rel) > 0 {
      return f"${ansi(colors, "2", util.version_id(remote_pkg.ver, remote_pkg.rel))} ${ansi(colors, "1;33", "->")} ${ansi(
        colors,
        "1;33",
        util.version_id(planned.ver, planned.rel),
      )}"
    }
  }

  let current = util.version_id(pkg.ver, pkg.rel)
  let next = util.version_id(planned.ver, planned.rel)

  if current == next {
    return ansi(colors, "2", current)
  }

  f"${ansi(colors, "2", current)} ${ansi(colors, "1;33", "->")} ${ansi(colors, "1;33", next)}"
}

proc print_world_plan(
  ordered: List[types.Package],
  planned: List[types.Package],
  reasons: Map[Str],
  local_names: Map[Bool],
  world_jobs: Int,
  remote_latest: Map[types.RemotePackage],
  arch: Str,
  staged_statuses: Map[Str],
  cross_build: Bool,
) [env, error] {
  let levels = world_plan_levels(ordered, cross_build)?
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
      let planned_pkg: types.Package = planned_by_name.get(pkg.name)?
      let annotation = world_plan_remote_annotation(pkg, planned_pkg, remote_latest)?
      var suffix = if annotation == "" { "" } else { f" ${ansi(colors, "1;31", annotation)}" }
      let reason = reasons.get(pkg.name, "")

      if reason != "" {
        suffix = f"${suffix} ${ansi(colors, "2", f"because ${reason}")}"
      }

      var version_text = ""

      if staged_statuses.has(pkg.name) {
        let status = staged_statuses.get(pkg.name)?

        version_text = f"${ansi(colors, "1;33", util.version_id(planned_pkg.ver, planned_pkg.rel))} ${ansi(
          colors,
          "2",
          f"stage: ${status} (local ${util.version_id(pkg.ver, pkg.rel)})",
        )}"
      } else {
        version_text = world_plan_version_text(pkg, planned_pkg, remote_latest, colors)?
      }

      print --flush f"  ${ansi(colors, "1;32", pkg.name)} ${version_text}${suffix}"
    }

    level += 1
  }
}

proc parse_world_jobs(value: Str, source: Str) [error] -> Result[Int] {
  let parsed = value.parse_int()?

  if parsed <= 0 {
    return Err(types.PmError.Usage(f"${source} must be a positive integer"))
  }

  parsed
}

proc parse_world_to_tranche(value: Str, source: Str) [error] -> Result[Int] {
  let parsed = value.parse_int()?

  if parsed < -1 {
    return Err(types.PmError.Usage(f"${source} must be -1, zero, or a positive integer"))
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

proc validate_world_declared_versions(packages: List[types.Package], remote_latest: Map[types.RemotePackage]) [error] {
  for pkg in packages {
    if remote_latest.has(pkg.name) and ! world_package_always_newer_than_remote(pkg.name, pkg.ver) {
      let rpkg: types.RemotePackage = remote_latest.get(pkg.name)?
      let cmp = compare_version_release(pkg.ver, pkg.rel, rpkg.ver, rpkg.rel)

      if cmp < 0 {
        return Err(
          types.PmError.PackageContract(
            f"${pkg.name} declares ${util.version_id(pkg.ver, pkg.rel)} but ${util.version_id(rpkg.ver, rpkg.rel)} is already published for this architecture; bump PKGBUILD.xsh rel explicitly",
          ),
        )
      }
    }
  }
}

proc world_latest_remote_map(index: List[types.RemotePackage], arch: Str) [error] -> Result[Map[types.RemotePackage]] {
  var latest: Map[types.RemotePackage] = {}

  for entry in index {
    if entry.arch == arch {
      if ! latest.has(entry.name) {
        latest[entry.name] = entry
      } else {
        let current: types.RemotePackage = latest.get(entry.name)?

        if compare_version_release(entry.ver, entry.rel, current.ver, current.rel) > 0 {
          latest[entry.name] = entry
        }
      }
    }
  }

  latest
}

pure native_cross_ldso_name(arch: Str) -> Str {
  if arch == "aarch64" {
    return "ld-musl-aarch64.so.1"
  }

  return f"ld-musl-${arch}.so.1"
}

type WorldBuildBatch = {
  built: List[types.BuiltPackage],
  failed: Bool,
}

type WorldBatchStageResult = {
  index: List[types.RemotePackage],
  failed: Bool,
}

pure native_cross_compiler_script(real: Path, build_root: Path, target_root: Path, target_arch: Str, cxx: Bool) -> Str {
  let cxx_text = if cxx { "true" } else { "false" }

  return f"""#!/bin/xsh
error NativeCrossCompilerError = Failed(message: Str)

proc run_compiler(argv: List[Any]) [process, error] {{
  let status = process.run(
    process.command_argv(
      fp"${real}",
      argv,
      env: {{LD_LIBRARY_PATH: "${build_root}/usr/lib:${build_root}/usr/lib/llvm23/lib", LIBCLANG_PATH: "${build_root}/usr/lib/llvm23/lib"}},
    ),
  )?

  if ! status.ok {{
    return Err(NativeCrossCompilerError.Failed(message: "compiler exited nonzero"))
  }}
}}

proc main(...argv: List[Str]) [fs, process, error] {{
  var cxx_args = []
  var cxx_libs = []
  var builtins_arg = []
  let builtins = fp"${target_root}/usr/lib/libclang_rt.builtins-${target_arch}.a"

  if fs.exists(builtins)? {{
    builtins_arg = [builtins]
  }}

  if ${cxx_text} {{
    let target_cxx = fp"${target_root}/usr/lib/llvm23/include/c++/v1"
    let build_cxx = fp"${build_root}/usr/lib/llvm23/include/c++/v1"
    let target_cxx_arch = fp"${target_root}/usr/lib/llvm23/include/${target_arch}-linux-musl/c++/v1"
    let unwind = fp"${target_root}/usr/lib/llvm23/lib/libunwind.a"

    if fs.exists(target_cxx)? {{
      cxx_args = ["-isystem", target_cxx]
    }} else if fs.exists(build_cxx)? {{
      cxx_args = ["-isystem", build_cxx]
    }}

    if fs.exists(target_cxx_arch)? {{
      cxx_args = cxx_args.extend(["-isystem", target_cxx_arch])
    }}

    cxx_libs = ["-L${target_root}/usr/lib/llvm23/lib", "-lc++", "-lc++abi"]

    if fs.exists(unwind)? {{
      cxx_libs = cxx_libs.push(unwind)
    }}

    cxx_libs = cxx_libs.push("-lm")
  }}

  let base = [
    fp"${real}",
    "--target=${target_arch}-linux-musl",
    "--sysroot=${target_root}",
    "-resource-dir",
    "${build_root}/usr/lib/llvm23/lib/clang/23",
  ]

  if "-c" in argv or "-S" in argv or "-E" in argv {{
    run_compiler(base.extend(cxx_args).extend(argv))?
    return
  }}

  if "-shared" in argv {{
    run_compiler(base.extend(["-fuse-ld=lld", "-nostdlib"]).extend(argv).push("-L${target_root}/usr/lib").extend(cxx_libs).extend(builtins_arg).push("-lc"))?
    return
  }}

  var link_argv = base.extend(["-fuse-ld=lld", "-nostdlib", fp"${target_root}/usr/lib/Scrt1.o", fp"${target_root}/usr/lib/crti.o"])
  link_argv = link_argv.extend(argv)
  link_argv = link_argv.push("-L${target_root}/usr/lib")
  link_argv = link_argv.extend(cxx_libs)
  link_argv = link_argv.extend(builtins_arg)
  link_argv = link_argv.extend(["-lc", fp"${target_root}/usr/lib/crtn.o", "-Wl,-dynamic-linker,/usr/lib/${native_cross_ldso_name(target_arch)}"])
  run_compiler(link_argv)?
}}

main(@args)?
"""
}

proc write_native_cross_tool_shims(build_root: Path, target_root: Path, target_arch: Str) [fs, error] {
  let bin = fp"${build_root}/.native-cross/bin"
  fs.mkdir(bin)?
  let clang = fp"${build_root}/usr/lib/llvm23/bin/clang-23"
  let clangxx = fp"${build_root}/usr/lib/llvm23/bin/clang++"

  for name in ["cc", "clang", "clang-23"] {
    let path_value = fp"${bin}/${name}"
    fs.write(path_value, native_cross_compiler_script(clang, build_root, target_root, target_arch, false))?
    fs.chmod(path_value, 0o755)?
  }

  for name in ["c++", "clang++"] {
    let path_value = fp"${bin}/${name}"
    fs.write(path_value, native_cross_compiler_script(clangxx, build_root, target_root, target_arch, true))?
    fs.chmod(path_value, 0o755)?
  }
}

proc build_world_package(
  repo_dir: Path,
  build_ctx: types.PmContext,
  target_staged_root: Path,
  build_staged_root: Path,
  pkg: types.Package,
  target_arch: Str,
  build_arch: Str,
  cross_build: Bool,
) [fs, net, process, env, time, error] -> Result[List[types.BuiltPackage]] {
  var built = []
  let started_at = time.now()
  let log_path = fp"${repo_dir}/packages/${target_arch}/${pkg.name}/build.log"
  print --flush ${pkg.name} world_package_id(pkg) "build:" "starting"
  let package_root = fp"${build_ctx.work}/world-build/${world_package_id(pkg)}/root"
  let package_build_root = fp"${build_ctx.work}/world-build/${world_package_id(pkg)}/build-root"
  let package_work = fp"${build_ctx.work}/world-build/${world_package_id(pkg)}/work"
  let package_out = fp"${build_ctx.work}/world-build/${world_package_id(pkg)}/out"
  let package_ctx: types.PmContext = {
    command: build_ctx.command,
    root: package_root,
    work: package_work,
    out: package_out,
  }
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
    XSH_PM_BUILD_LOG = log_path.display()
    XSH_PM_BUILD_ROOT = package_path_root.display()
    XSH_PM_BUILD_CHROOT = build_chroot
  } {
    match pm_build.build_packages(package_ctx, [pkg]) {
      Ok(items) => built = items
      Err(err) => return Err(err)
    }
  } ?

  let tarball_size = if built.len() > 0 {
    local.compressed_package_size(fs.metadata(built[0].tarball)?.size)
  } else {
    "0K"
  }

  print --flush ${pkg.name} world_package_id(pkg) "build:" "finished" time.duration_compact(
    (time.now() - started_at) / 1000,
  ) "size:" $tarball_size "log:" $log_path

  built
}

proc append_world_package_log(log_path: Path, line: Str) [fs, error] {
  let existing = if fs.exists(log_path)? { log_path.read_text()? } else { "" }
  fs.mkdir(log_path.parent.parent.parent)?
  fs.mkdir(log_path.parent.parent)?
  fs.mkdir(log_path.parent)?

  fs.write(
    log_path,
    f"""${existing}${line}
""",
  )?
}

proc build_world_package_or_empty(
  repo_dir: Path,
  build_ctx: types.PmContext,
  target_staged_root: Path,
  build_staged_root: Path,
  pkg: types.Package,
  target_arch: Str,
  build_arch: Str,
  cross_build: Bool,
) [fs, net, process, env, time, error] -> Result[WorldBuildBatch] {
  let started_at = time.now()
  let log_path = fp"${repo_dir}/packages/${target_arch}/${pkg.name}/build.log"

  match build_world_package(
    repo_dir,
    build_ctx,
    target_staged_root,
    build_staged_root,
    pkg,
    target_arch,
    build_arch,
    cross_build,
  ) {
    Ok(built) => return Ok({built, failed: false})
    Err(err) => {
      append_world_package_log(log_path, f"world-build error: ${err.message}")?

      eprint --flush ${pkg.name} world_package_id(pkg) "build:" "failed" time.duration_compact(
        (time.now() - started_at) / 1000,
      ) "log:" $log_path

      return Ok({built: [], failed: true})
    }
  }
}

proc remove_world_unowned_install_conflicts(root: Path, built: List[types.BuiltPackage]) [fs, error] {
  let installed_owners = local.load_installed_owners(root)?

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
  fs.exists(util.package_db_path(root, name))?
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

proc install_world_built_packages(ctx: types.PmContext, built: List[types.BuiltPackage]) [fs, process, env, error] {
  if built.len() > 0 {
    install.install_built_packages(ctx, built)?
  }
}

proc stage_world_source_mirror(repo_dir: Path, item: types.BuiltPackage, arch: Str) [fs, error] {
  if item.pkg.upstream_sources.len() == 0 or ! item.pkg.source_mirror {
    return
  }

  let package_out = fp"${repo_dir}/.work/world-build/${world_package_id(item.pkg)}/out"
  let source = util.source_mirror_path_for_arch(package_out, item.pkg, arch)
  let manifest = util.source_manifest_path_for_arch(package_out, item.pkg, arch)

  if ! fs.exists(source)? or ! fs.exists(manifest)? {
    return Err(types.PmError.SourceNotFound(f"${item.pkg.name} world build did not produce a source mirror"))
  }

  let manifest_record: Record = json.read(manifest)?
  let expected: Str = manifest_record.get("archive_sha256")?

  if expected != hash.sha256(source)?.hex() {
    return Err(types.PmError.SourceChecksum(f"${item.pkg.name} world source manifest hash mismatch"))
  }

  let repo_out = fp"${repo_dir}/.out"
  fs.mkdir(util.source_mirror_path_for_arch(repo_out, item.pkg, arch).parent)?
  fs.copy(source, util.source_mirror_path_for_arch(repo_out, item.pkg, arch), overwrite: true)?
  fs.copy(manifest, util.source_manifest_path_for_arch(repo_out, item.pkg, arch), overwrite: true)?
}

# Keep post-build staging in a separate procedure. The lowered world-plan
# procedure otherwise overflows while evaluating the batch result and its
# remote-metadata comparison, even though the package batch is already built.
proc stage_world_build_batch(
  repo_dir: Path,
  upload_ctx: types.PmContext,
  root_ctx: types.PmContext,
  build_ctx: types.PmContext,
  root: Path,
  build_root: Path,
  built: List[types.BuiltPackage],
  index: List[types.RemotePackage],
  target_arch: Str,
  cross_build: Bool,
) [fs, net, process, env, time, error] -> Result[WorldBatchStageResult] {
  var updated_index = index

  if built.len() == 0 {
    return Ok({index: updated_index, failed: true})
  }

  for item in built {
    stage_world_source_mirror(repo_dir, item, target_arch)?
    updated_index = repo.stage_built_package(repo_dir, upload_ctx, updated_index, item)?
  }

  remove_world_unowned_install_conflicts(root, built)?
  install_world_built_packages(root_ctx, built)?

  if ! cross_build and root.display() != build_root.display() {
    remove_world_unowned_install_conflicts(build_root, built)?
    install_world_built_packages(build_ctx, built)?
  }

  return Ok({index: updated_index, failed: false})
}

proc read_world_state(repo_dir: Path) [fs, error] -> Result[Record] {
  let state_path = world_state_path(repo_dir)

  if ! fs.exists(state_path)? {
    return Err(types.PmError.PackageTarball(f"${state_path.display()} is missing; run world-plan --build first"))
  }

  json.read(state_path)?
}

proc write_world_state(
  repo_dir: Path,
  fingerprint: Str,
  packages: List[types.Package],
  built_names: Map[Bool],
  unchanged_names: Map[Bool],
  complete: Bool,
) [fs, env, error] {
  let state_path = world_state_path(repo_dir)
  fs.mkdir(state_path.parent)?
  let arch = util.machine_arch()?
  var built = []
  var proofed = []
  var unchanged = []

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
  packages: List[types.Package],
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
    let old_unchanged = if state.has("unchanged") { state.get("unchanged")? } else { [] }
    var built_names: Map[Bool] = {}
    var unchanged_names: Map[Bool] = {}

    for pkg in packages {
      let id = world_package_id(pkg)

      if id in old_unchanged {
        built_names[pkg.name] = true
        unchanged_names[pkg.name] = true
      } else if id in old_built and id in old_proofed {
        built_names[pkg.name] = true
      }
    }

    write_world_state(repo_dir, fingerprint, packages, built_names, unchanged_names, false)?
    return read_world_state(repo_dir)?
  }

  state
}

proc world_staged_package_statuses(
  repo_dir: Path,
  fingerprint: Str,
  root: Path,
  build_root: Path,
  planned: List[types.Package],
  cross_build: Bool,
) [fs, env, error] -> Result[Map[Str]] {
  let state = ensure_world_state_compatible(repo_dir, fingerprint, planned)?
  let built: List[Str] = state.get("built")?
  let proofed: List[Str] = state.get("proofed")?
  let unchanged = if state.has("unchanged") { state.get("unchanged")? } else { [] }
  var statuses: Map[Str] = {}

  for pkg in planned {
    let id = world_package_id(pkg)

    if id in unchanged and world_stage_package_present_in_roots(root, build_root, pkg.name, cross_build)? {
      statuses[pkg.name] = "unchanged"
    } else if id in built and id in proofed and world_stage_package_present_in_roots(
      root,
      build_root,
      pkg.name,
      cross_build,
    )? {
      statuses[pkg.name] = "cached"
    }
  }

  statuses
}

proc verify_staged_entry_tarball(repo_dir: Path, entry: types.RemotePackage) [fs, error] {
  if entry.metapackage {
    return
  }

  let tarball = fp"${repo_dir}/${entry.tarball}"

  if ! fs.exists(tarball)? {
    return Err(types.PmError.PackageTarball(f"${tarball.display()} is missing"))
  }

  let metadata = fs.metadata(tarball)?

  if metadata.size != entry.size {
    return Err(types.PmError.PackageTarball(f"${tarball.display()} size mismatch"))
  }

  let actual = hash.sha256(tarball)?.hex()

  if actual != entry.sha256 {
    return Err(types.PmError.PackageTarball(f"${tarball.display()} checksum mismatch"))
  }
}

proc verify_staged_entry_metadata(repo_dir: Path, entry: types.RemotePackage) [fs, error] {
  if entry.metapackage {
    return
  }

  if entry.metadata == "" {
    return Err(
      types.PmError.PackageTarball(f"${entry.name} ${util.version_id(entry.ver, entry.rel)} has no metadata sidecar"),
    )
  }

  let metadata = fp"${repo_dir}/${entry.metadata}"

  if ! fs.exists(metadata)? {
    return Err(types.PmError.PackageTarball(f"${metadata.display()} is missing"))
  }

  let metadata_record: Record = json.read(metadata)?
  let sidecar_hash: Str = metadata_record.get("metadata_sha256")?

  if sidecar_hash == "" {
    return Err(types.PmError.PackageTarball(f"${metadata.display()} has empty metadata hash"))
  }
}

proc verify_world_stage(repo_dir: Path, packages: List[types.Package], fingerprint: Str) [fs, env, error] {
  let state = read_world_state(repo_dir)?
  let stored_fingerprint: Str = state.get("fingerprint")?

  if stored_fingerprint != fingerprint {
    return Err(
      types.PmError.PackageContract(f"${world_state_path(repo_dir).display()} belongs to a different world plan"),
    )
  }

  let complete: Bool = state.get("complete")?

  if ! complete {
    return Err(types.PmError.PackageTarball("world staging repo is incomplete; run world-plan --build first"))
  }

  let built: List[Str] = state.get("built")?
  let proofed: List[Str] = state.get("proofed")?
  let unchanged = if state.has("unchanged") { state.get("unchanged")? } else { [] }
  let index_path = fp"${repo_dir}/index.json"

  if ! fs.exists(index_path)? {
    return Err(types.PmError.PackageTarball(f"${index_path.display()} is missing"))
  }

  let index = remote.load_remote_index_from(index_path)?

  for entry in index {
    verify_staged_entry_tarball(repo_dir, entry)?
    verify_staged_entry_metadata(repo_dir, entry)?
  }

  for pkg in packages {
    let id = world_package_id(pkg)

    if id not in built and id not in unchanged {
      return Err(types.PmError.PackageTarball(f"${id} has not been built in the world stage"))
    }

    if id not in proofed and id not in unchanged {
      return Err(types.PmError.PackageTarball(f"${id} has not been proved in the world stage"))
    }
  }
}

proc audit_world_elf_dependencies(root: Path, packages: List[types.Package]) [fs, env, error] {
  let providers = elfdeps.collect_library_providers(root)?
  var package_deps: Map[List[Str]] = {}

  for pkg in packages {
    package_deps[pkg.name] = pkg.deps
  }

  var failures: List[elfdeps.ElfDependencyFailure] = []

  for pkg in packages {
    let allowed = elfdeps.runtime_dependency_closure(pkg.deps, package_deps)
    let db = util.package_db_path(root, pkg.name)
    continue unless fs.exists(db)?
    let manifest = local.load_manifest(db)?

    for rel_path in manifest {
      let path_value = fp"${root}/${rel_path}"

      if path_value.exists()? {
        failures = failures.extend(
          elfdeps.installed_file_elf_dependency_failures(pkg.name, allowed, rel_path, path_value, providers)?,
        )
      }
    }
  }

  if failures.len() > 0 {
    for failure in failures {
      eprint f"world-audit missing ELF dep: ${failure.pkg}: ${failure.file.display()} needs ${failure.soname} from ${failure.provider}"
    }

    return Err(
      types.PmError.PackageContract(
        f"world ELF dependency audit found ${failures.len()} undeclared runtime dependency edge(s)",
      ),
    )
  }

  print --flush "world-audit" "elf-deps" "ok"
}

## Plans, builds, and optionally uploads the selected world package set.
export proc world_plan_repo(argv: List[Str]) [fs, net, process, env, time, error] {
  let opts: WorldPlanOptions = cli.parse(
    argv |> drop(1),
    {
      pkgdirs: {
        form: "...PKGDIR",
        repeated: true,
        required: true,
      },
      arch: {
        form: "--arch ARCH",
        default: host_world_arch()?,
        help: "plan for ARCH (arm64 maps to aarch64)",
      },
      build: {
        form: "--build",
        default: false,
        help: "build all planned packages into the world staging repo",
      },
      upload: {
        form: "--upload",
        default: false,
        help: "upload only after the world staging repo is complete",
      },
      to_tranche: {
        form: "--to-tranche N",
        default: -1,
        min: -1,
        help: "with --build, stop after tranche N and leave stage resumable",
      },
      jobs: {
        form: "-j --jobs N",
        kind: "Int",
        default: default_world_jobs()?,
        min: 1,
        help: "build jobs per tranche",
      },
    },
    "pm world-plan",
  )?

  let raw_args = opts.pkgdirs
  let build_requested = opts.build
  let upload_requested = opts.upload
  let world_jobs = opts.jobs
  let target_arch = validate_world_arch(opts.arch)?
  let to_tranche = parse_world_to_tranche(f"${opts.to_tranche}", "--to-tranche")?
  let host_arch = host_world_arch()?
  let world_build_arch = validate_world_arch(util.build_arch()?)?
  let native_cross_requested = (env.get("XSH_PM_NATIVE_CROSS") ?? "0") == "1"
  let cross_build = target_arch != world_build_arch

  if build_requested and target_arch != host_arch and ! native_cross_requested {
    return Err(types.PmError.Usage(f"world-plan --build for ${target_arch} is not supported on host ${host_arch}"))
  }

  if build_requested and cross_build and ! native_cross_requested {
    return Err(types.PmError.Usage("world-plan native cross build requires XSH_PM_NATIVE_CROSS=1"))
  }

  if build_requested and world_build_arch != host_arch {
    return Err(types.PmError.Usage(f"world-plan build arch ${world_build_arch} must match host ${host_arch}"))
  }

  let colors = color_enabled()
  print --flush ansi(colors, "1;34", "world-plan loading") ansi(colors, "2", f"packages for ${target_arch}")
  let package_dirs = expand_world_package_dirs(raw_args)?
  let pm_module_root = pm_module_root_path()?
  var packages = []

  env {
    XSH_PM_ARCH = target_arch
    XSH_PM_TARGET_ARCH = target_arch
    XSH_PM_BUILD_ARCH = world_build_arch
    XSH_MODULE_PATH = f"${pm_module_root.display()}:${env.get("XSH_MODULE_PATH") ?? ""}"
  } {
    packages = local.load_package_dirs(package_dirs)?
  } ?

  let fingerprint = world_plan_content_hash(packages, target_arch)?
  let cache_key = world_plan_cache_key(packages, target_arch)
  let repo_dir = world_cache_repo_dir(cache_key)?
  let root = fp"${repo_dir}/.world/root"
  let build_root = if cross_build { fp"${repo_dir}/.world/build-root" } else { root }
  let work = fp"${repo_dir}/.work"
  let out = fp"${repo_dir}/.out"
  let root_ctx: types.PmContext = {command: "world-plan", root, work, out}
  let build_ctx: types.PmContext = {command: "world-plan", root: build_root, work, out}
  let upload_ctx: types.PmContext = {...build_ctx, command: "upload"}
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
  var index = []

  if fs.exists(index_path)? {
    index = remote.load_remote_index_from(index_path)?
  }

  print --flush f"${ansi(colors, "1;36", "world-repo")} ${ansi(colors, "2", repo_dir.display())}"
  print --flush ansi(colors, "1;34", "world-plan fetching") ansi(colors, "2", "remote index")
  let repo_urls = remote.load_repo_urls()?
  var remote_index = []
  var remote_latest: Map[types.RemotePackage] = {}
  var build_remote_latest: Map[types.RemotePackage] = {}

  if repo_urls.repo != "" {
    remote_index = remote.load_remote_index_from_repo(repo_urls.repo, out)?
    remote_latest = world_latest_remote_map(remote_index, target_arch)?
    build_remote_latest = world_latest_remote_map(remote_index, world_build_arch)?

    if build_requested or upload_requested {
      validate_world_declared_versions(packages, remote_latest)?
    }
  }

  let local_names = buildroot.local_package_names(packages)
  let ordered = order_world_build_packages(build_root, packages, index, target_arch, ! cross_build)?
  let plan = planned_world_packages(ordered, local_names, remote_latest)?
  let planned = plan.packages
  let planned_by_name = planned_world_package_map(planned)
  var staged_statuses: Map[Str] = {}

  if build_requested {
    staged_statuses = world_staged_package_statuses(repo_dir, fingerprint, root, build_root, planned, cross_build)?
  }

  print_world_plan(ordered, planned, plan.reasons, local_names, world_jobs, remote_latest, target_arch, staged_statuses, cross_build)?

  if build_requested {
    let state = ensure_world_state_compatible(repo_dir, fingerprint, planned)?
    let recorded_built: List[Str] = state.get("built")?
    let recorded_proofed: List[Str] = state.get("proofed")?
    let recorded_unchanged = if state.has("unchanged") { state.get("unchanged")? } else { [] }

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
    let levels = world_plan_levels(ordered, cross_build)?
    let max_level = world_plan_max_level(ordered, levels)
    let build_max_level = if to_tranche >= 0 and to_tranche < max_level { to_tranche } else { max_level }
    let build_local_names = if cross_build { map.empty() } else { local_names }
    print --flush ansi(colors, "1;34", "world-build preparing") ansi(colors, "2", "chroot base")
    buildroot.install_chroot_base_for_arch(root_ctx, local_names, false, target_arch)?

    if build_root.display() != root.display() {
      buildroot.install_chroot_base_for_arch(build_ctx, build_local_names, true, world_build_arch)?
    }

    var level = 0

    while level <= build_max_level {
      let tranche = world_packages_at_level(ordered, levels, level)
      var pending = []
      var pending_originals = []

      for pkg in tranche {
        let build_pkg: types.Package = planned_by_name.get(pkg.name)?
        let id = world_package_id(build_pkg)

        if id in recorded_unchanged and world_stage_package_present_in_roots(root, build_root, pkg.name, cross_build)? {
          built_names[pkg.name] = true
          unchanged_names[pkg.name] = true
          print --flush ${pkg.name} $id "stage:" "unchanged"
        } else if id in recorded_built and id in recorded_proofed and world_stage_package_present_in_roots(
          root,
          build_root,
          pkg.name,
          cross_build,
        )? {
          built_names[pkg.name] = true
          print --flush ${pkg.name} $id "stage:" "cached"
        } else {
          var build_dependency_names = effective_world_build_dependencies(pkg, cross_build)

          if world_dependency_is_seeded(pkg, "zlib", cross_build) and "zlib" not in build_dependency_names {
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

          buildroot.install_remote_dependency_set_for_arch(root_ctx, missing_root_dependencies, target_arch)?

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

          buildroot.install_remote_dependency_set_for_arch(build_ctx, missing_build_dependencies, world_build_arch)?
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

        var built_batches: List[WorldBuildBatch] = []

        if world_jobs == 1 {
          for pkg in pending {
            built_batches = built_batches.push(
              build_world_package_or_empty(
                repo_dir,
                build_ctx,
                root,
                build_root,
                pkg,
                target_arch,
                world_build_arch,
                cross_build,
              )?,
            )
          }
        } else {
          built_batches = pending
            |> par-map --jobs=world_jobs { |pkg|
              build_world_package_or_empty(
                repo_dir,
                build_ctx,
                root,
                build_root,
                pkg,
                target_arch,
                world_build_arch,
                cross_build,
              )
            }
        }

        # Remote metadata comparison is intentionally outside this required
        # path until lowered calls can evaluate it without overflowing.
        var pending_index = 0
        var tranche_errors = []

        for batch in built_batches {
          let original_pkg = pending_originals[pending_index]
          let build_pkg = pending[pending_index]
          let result = stage_world_build_batch(
            repo_dir,
            upload_ctx,
            root_ctx,
            build_ctx,
            root,
            build_root,
            batch.built,
            index,
            target_arch,
            cross_build,
          )?
          index = result.index

          if result.failed {
            let pkg_id = world_package_id(build_pkg)
            let msg = f"${original_pkg.name} ${pkg_id}"
            tranche_errors = tranche_errors.push(msg)
            eprint f"world-build: ${msg} failed"
          } else {
            built_names[original_pkg.name] = true

            json.write(index_path, index)?
            write_world_state(repo_dir, fingerprint, planned, built_names, unchanged_names, false)?
          }

          pending_index += 1
        }

        if tranche_errors.len() > 0 {
          eprint f"tranche ${level}: ${tranche_errors.len()}/${pending.len()} failed:"

          for error in tranche_errors {
            eprint f"  ${error}"
          }

          abort(3)
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
    audit_world_elf_dependencies(root, planned)?
    print --flush "world-plan" "uploading" "repository export"
    repo.upload_repo_export(["upload-repo-export", repo_dir.display()])?
  }
}
