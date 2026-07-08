use build as pm_build
use buildroot
use extensions
use install
use local
use pm.env as pm_env
use remote
use repo
use types
use util
use world

pure usage(message: Str) -> Error {
  PmError.Usage(f"usage: ${message}")
}

proc parse_pm_cli(argv: List[Str]) [error] -> Result[Cli] {
  let path_types = {root: "Path", work: "Path", out: "Path"}

  let commands = {
    smoke: {positionals: ["root", "work", "out"], types: path_types, rest: "raw", min_rest: 1},
    install: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    remove: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    list: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    info: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    search: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    tree: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    outdated: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    upgrade: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    update: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    checksum: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    update_checksums: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    download: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    refresh_index: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    auth: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    upload: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
    help_ext: {positionals: ["root", "work", "out"], types: path_types, rest: "raw"},
  }

  let parsed: Cli = cli.commands(
    argv,
    rootless_default: "smoke",
    commands: commands,
    fallback_command: {
      positionals: ["action", "root", "work", "out"],
      types: path_types,
      rest: "raw",
      command_like: true,
    },
  )?

  {
    command: parsed.command.replace("_", "-"),
    action: parsed.action,
    root: parsed.root,
    work: parsed.work,
    out: parsed.out,
    raw: parsed.raw,
  }
}

proc print_help() [] {
  print "usage: pm COMMAND [ARG...]\n\ntop-level commands:\n  build REPO_DIR PKGDIR...\n  world-plan PKGDIR... [--arch ARCH] [--build] [--upload] [--sync-rels] [--to-tranche N] [-j N|--jobs N]\n  build-install ROOT BUILD_ROOT WORK OUT PKGDIR...\n  build-set REPO_DIR PKGDIR...\n  build-upload-set REPO_DIR PKGDIR...\n  upload-set REPO_DIR PKGDIR...\n  upload-repo-export REPO_DIR\n\nroot commands:\n  install [ROOT WORK OUT] PKG...\n  remove [ROOT WORK OUT] PKG...\n  list [ROOT WORK OUT]\n  info [ROOT WORK OUT] PKG...\n  tree [ROOT WORK OUT] [PKG...]\n  search [ROOT WORK OUT] QUERY [PKGDIR...]\n  outdated [ROOT WORK OUT] PKGDIR...\n  update [ROOT WORK OUT] PKGDIR...\n  upgrade [ROOT WORK OUT] PKGDIR...\n  checksum [ROOT WORK OUT] PKGDIR...\n  update-checksums [ROOT WORK OUT] PKGDIR...\n  download [ROOT WORK OUT] PKGDIR...\n  refresh-index [ROOT WORK OUT]\n  auth [ROOT WORK OUT] [TOKEN]\n  upload [ROOT WORK OUT] PKGDIR...\n  help-ext [ROOT WORK OUT]\n\nWhen run from inside this package repo, root commands default ROOT, WORK, and OUT\nto .root, .work, and .out at the repo root.\n\nworld-plan stores its staging repo under ~/.cache/laputa/world-<hash>, where\nthe hash covers the selected package set and arch. The state fingerprint covers\nselected PKGBUILD.xsh files so package edits invalidate an in-progress world.\n"
}

proc build_local_packages(
  ctx: PmContext,
  raw: List[Str],
  allow_installed_deps: Bool,
) [fs, net, process, env, time, error] -> Result[List[BuiltPackage]] {
  let dirs = paths_from_args(raw)?
  let packages = load_package_dirs(dirs)?
  let ordered = order_packages(ctx.root, packages, allow_installed_deps)?
  pm_build.build_packages(ctx, ordered)?
}

proc build_and_install_local_packages(
  ctx: PmContext,
  raw: List[Str],
  allow_installed_deps: Bool,
) [fs, net, process, env, time, error] {
  let built = build_local_packages(ctx, raw, allow_installed_deps)?
  install_built_packages(ctx, built)?
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

proc command_upgrade(ctx: PmContext, raw: List[Str]) [fs, net, process, env, time, error] {
  let packages = load_local_packages(raw)?
  let upgrade_names = collect_upgrade_names(ctx.root, packages)?

  if upgrade_names.len() > 0 {
    let selected = filter_packages_by_names(packages, upgrade_names)?
    let ordered = order_packages(ctx.root, selected, true)?
    let built = pm_build.build_packages(ctx, ordered)?
    install_built_packages(ctx, built)?
  }
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
      PATH = pm_env.build_path(build_root, env.get("PATH") ?? "")
    } {
      built = pm_build.build_packages(build_ctx, [pkg])?
    } ?

    install_built_packages(root_ctx, built)?

    if root.display() != build_root.display() {
      install_built_packages(build_ctx, built)?
    }
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

  let packages = load_package_dirs(paths_from_args(raw_args)?)?
  let local_names = local_package_names(packages)
  let ordered = packages
  var built_names: Map[Bool] = {}

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
      PATH = pm_env.build_path(build_root, env.get("PATH") ?? "")
    } {
      built = pm_build.build_packages(build_ctx, [pkg])?
    } ?

    for item in built {
      index = stage_built_package(repo_dir, upload_ctx, index, item)?
      built_names[item.pkg.name] = true
    }

    json.write(index_path, index)?
    fs.remove(remote_index_cache_path(out), missing_ok: true)?
  }
}

proc build_upload_set_repo(argv: List[Str]) [fs, net, process, env, time, error] {
  build_set_repo(argv)?
  upload_set_repo(argv)?
}

proc build_prepared_package_command(argv: List[Str]) [fs, process, env, error] {
  if argv.len() != 5 {
    return Err(usage("pm build-prepared-package PKGDIR SRC DEST TARBALL"))
  }

  pm_build.build_prepared_package(
    path.absolute(fp"${argv[1]}")?,
    path.absolute(fp"${argv[2]}")?,
    path.absolute(fp"${argv[3]}")?,
    path.absolute(fp"${argv[4]}")?,
  )?
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

export proc run_pm_cli(argv: List[Str]) [fs, net, process, env, time, error] {
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
