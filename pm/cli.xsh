##! PM cli operations and shared package-manager policy.
use build as pm_build
use buildroot
use catalog
use extensions
use fingerprint as pm_fingerprint
use graph
use install
use local
use pm.env as pm_env
use plan as pm_plan
use plan_json as pm_plan_json
use policy
use remote
use repo
use sources
use types
use util
use world as pm_world

# Explicit arguments for catalog validation without a plan write.
type RepoCheckArgs = {repo: Path}

# Explicit arguments for deterministic BuildPlan generation.
type RepoPlanArgs = {
  repo: Path,
  all: Bool,
  roots: List[Str],
  target: Str,
  output: Path,
}

# Explicit arguments for displaying one persisted BuildPlan.
type RepoShowArgs = {input: Path}

# The intermediate typed repository-planning command surface.
type RepoCommand = LegacyCommand | RepoCheck(RepoCheckArgs) | RepoPlan(RepoPlanArgs) | RepoShow(RepoShowArgs) | RepoHelp(Str)

type RepoCheckOptions = {repo: Str}
type RepoPlanOptions = {repo: Str, all: Bool, roots: List[Str], target: Str, output: Path}
type RepoShowOptions = {input: Path}

pure repo_help_text() -> Str {
  """usage: pm repo COMMAND [OPTIONS]

repository planning commands:
  check [--repo PATH]                    validate the typed package catalog
  plan [--repo PATH] (--all | --root PACKAGE...) --output PLAN [--target aarch64-linux-musl]
                                         resolve and atomically save a BuildPlan
  show PLAN                              verify and render a saved BuildPlan
"""
}

pure repo_plan_help_text() -> Str {
  """usage: pm repo plan [--repo PATH] (--all | --root PACKAGE...) --output PLAN [--target aarch64-linux-musl]

--all and --root are mutually exclusive. --output is required.
"""
}

pure repo_check_help_text() -> Str {
  """usage: pm repo check [--repo PATH]
"""
}

pure repo_show_help_text() -> Str {
  """usage: pm repo show PLAN
"""
}

pure tail_after(argv: List[Str], start: Int) -> List[Str] {
  var result: List[Str] = []
  var index = start

  while index < argv.len() {
    result = result.push(argv[index])
    index += 1
  }

  result
}

proc repo_default_root() [fs, error] -> Result[Path] {
  let root = current_pm_repo_root()?

  if root.display() == "" {
    return Err(types.PmError.Usage("pm repo requires --repo outside a package repository"))
  }

  root
}

proc resolve_repo_root(raw: Str) [fs, error] -> Result[Path] {
  if raw == "" {
    return repo_default_root()?
  }

  path.absolute(fp"${raw}")?
}

# Parses every new repository-planning command through typed option schemas.
# Legacy executor commands retain their historical parser until their later cutover.
proc parse_repo_command(argv: List[Str]) [fs, error] -> Result[RepoCommand] {
  if argv.len() == 0 or argv[0] != "repo" {
    return LegacyCommand
  }

  if argv.len() == 1 or argv[1] in ["-h", "--help", "help"] {
    return RepoHelp(repo_help_text())
  }

  let action = argv[1]
  let args = tail_after(argv, 2)

  if args.len() == 1 and args[0] in ["-h", "--help", "help"] {
    match action {
      "check" => return RepoHelp(repo_check_help_text())
      "plan" => return RepoHelp(repo_plan_help_text())
      "show" => return RepoHelp(repo_show_help_text())
      _ => return Err(types.PmError.Usage(f"unknown pm repo command ${action}"))
    }
  }

  match action {
    "check" => {
      var parsed: RepoCheckOptions = {repo: ""}
      match cli.parse(args, {repo: {form: "--repo PATH", default: ""}}, "pm repo check") {
        Ok(value) => parsed = value
        Err(problem) => return Err(problem)
      }
      var root: Path = p""
      match resolve_repo_root(parsed.repo) {
        Ok(value) => root = value
        Err(problem) => return Err(problem)
      }
      return RepoCheck({repo: root})
    }
    "plan" => {
      var parsed: RepoPlanOptions = {
        repo: "",
        all: false,
        roots: [],
        target: "aarch64-linux-musl",
        output: p"",
      }
      match cli.parse(
        args,
        {
          repo: {form: "--repo PATH", default: ""},
          all: {form: "--all", default: false},
          roots: {form: "--root PACKAGE", repeated: true},
          target: {form: "--target TARGET", default: "aarch64-linux-musl"},
          output: {form: "--output PLAN", kind: "Path", required: true},
        },
        "pm repo plan",
      ) {
        Ok(value) => parsed = value
        Err(problem) => return Err(problem)
      }

      if parsed.all == (parsed.roots.len() > 0) {
        return Err(usage("pm repo plan requires exactly one of --all or one-or-more --root"))
      }

      match types.parse_target(parsed.target) {
        Ok(_) => {}
        Err(problem) => return Err(problem)
      }
      var root: Path = p""
      match resolve_repo_root(parsed.repo) {
        Ok(value) => root = value
        Err(problem) => return Err(problem)
      }
      return RepoPlan({
        repo: root,
        all: parsed.all,
        roots: parsed.roots,
        target: parsed.target,
        output: parsed.output,
      })
    }
    "show" => {
      var parsed: RepoShowOptions = {input: p""}
      match cli.parse(args, {input: {form: "PLAN", kind: "Path", required: true}}, "pm repo show") {
        Ok(value) => parsed = value
        Err(problem) => return Err(problem)
      }
      return RepoShow({input: parsed.input})
    }
    _ => return Err(types.PmError.Usage(f"unknown pm repo command ${action}"))
  }
}

proc cli_pm_source_root(repo_root: Path) [fs, env, error] -> Result[Path] {
  if fs.exists(fp"${repo_root}/pm.xsh")? and fs.exists(fp"${repo_root}/pm")? {
    return path.absolute(repo_root)?
  }

  for raw in (env.get("XSH_MODULE_PATH") ?? "").split(":") {
    continue when raw == ""
    let candidate = fp"${raw}"

    if fs.exists(fp"${candidate}/pm.xsh")? and fs.exists(fp"${candidate}/pm")? {
      return path.absolute(candidate)?
    }
  }

  let current = current_pm_repo_root()?

  if current.display() != "" and fs.exists(fp"${current}/pm")? {
    return current
  }

  return Err(types.PmError.PackageContract("cannot locate PM source root for BuildPlan executor identity"))
}

proc cli_xsh_runner() [fs, process, env, error] -> Result[Path] {
  let configured = (env.get("XSH_HOST") ?? "").trim()

  if configured != "" {
    return path.absolute(fp"${configured}")?
  }

  process.which("xsh")?
}

proc cli_core_root(pm_root: Path) [fs, env, error] -> Result[Path] {
  let configured = (env.get("XSH_CORE_ROOT") ?? "").trim()

  if configured != "" {
    let root = path.absolute(fp"${configured}")?

    if fs.exists(root)? {
      return root
    }

    return Err(types.PmError.PackageContract(f"XSH_CORE_ROOT ${root.display()} is missing"))
  }

  for candidate in [p"/usr/lib/xsh/core", fp"${pm_root.parent}/xsh/core"] {
    if fs.exists(candidate)? {
      return candidate
    }
  }

  return Err(types.PmError.PackageContract("cannot locate XSH core applets for BuildPlan executor identity; set XSH_CORE_ROOT"))
}

proc cli_executor_identity(repo_root: Path) [fs, process, env, error] -> Result[types.ExecutorIdentity] {
  let pm_root = cli_pm_source_root(repo_root)?
  let xsh = cli_xsh_runner()?
  let xshi = fp"${xsh.parent}/xshi"
  let xsht = fp"${xsh.parent}/xsht"

  if ! fs.exists(xshi)? or ! fs.exists(xsht)? {
    return Err(types.PmError.PackageContract(f"BuildPlan executor needs xsh, xshi, and xsht beside ${xsh.display()}"))
  }

  {
    format: "laputa-pm-executor-1",
    pm_sha256: pm_fingerprint.pm_tree(pm_root)?,
    xsh_sha256: pm_fingerprint.runners(xsh, xshi, xsht)?,
    core_sha256: pm_fingerprint.core_tree(cli_core_root(pm_root)?)?,
  }
}

proc remote_entry_digest(value: types.RemotePackage) [error] -> Result[Str] {
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

proc remote_index_digest(out: Path) [fs, error] -> Result[Str] {
  let index_path = util.remote_index_cache_path(out)

  if index_path.exists()? {
    return hash.sha256(index_path)?.hex()
  }

  bytes.from_text("[]\n").sha256().hex()
}

proc remote_snapshot_for_plan(out: Path) [fs, net, env, time, error] -> Result[types.RemoteSnapshot] {
  var index: List[types.RemotePackage] = []
  let cache = util.remote_index_cache_path(out)
  let offline = (env.get("XSH_PM_OFFLINE") ?? "") == "1"

  if cache.exists()? {
    index = remote.load_cached_remote_index(out)?
  } else if ! offline {
    let urls = remote.load_repo_urls()?

    for endpoint in [urls.public_repo, urls.repo] {
      continue when endpoint == ""
      let fetched = remote.load_remote_index_from_repo(endpoint, out)?

      for entry in fetched {
        index = remote.upsert_remote_package(index, entry)?
      }
    }

    remote.write_remote_index_cache(out, index)?
  }

  let index_sha256 = remote_index_digest(out)?
  var packages: List[types.RemotePlanArtifact] = []

  for entry in index {
    continue unless entry.arch == "aarch64"
    packages = packages.push(remote.plan_artifact_from_package(entry)?)
  }

  {target: types.Aarch64LinuxMusl, index_sha256, packages}
}

proc command_repo_check(args: RepoCheckArgs) [fs, env, error] {
  let value = catalog.load(args.repo)?
  let edges = graph.edges(value, policy.aarch64_docker())?
  print "repo" "check" value.packages.len() "packages" edges.len() "edges"
}

proc command_repo_plan(args: RepoPlanArgs) [fs, net, process, env, time, error] {
  let target = types.parse_target(args.target)?
  let policy_value = policy.aarch64_docker()

  if target != policy_value.target {
    return Err(types.PmError.PackageContract(f"unsupported planning target ${args.target}"))
  }

  let value = pm_plan.resolve(
    catalog.load(args.repo)?,
    remote_snapshot_for_plan(args.output.parent)?,
    policy_value,
    args.roots,
    args.all,
    cli_executor_identity(args.repo)?,
  )?

  # Keep the public plan_json.write contract intact. The current indexed XSH
  # runner cannot compile a direct reachable call to that exported spelling;
  # write_plan is its identical typed DTO and atomic-write implementation.
  pm_plan_json.write_plan(args.output, value)?
  print pm_plan.render(value, false)?
}

proc command_repo_show(args: RepoShowArgs) [fs, error] {
  print pm_plan.render(pm_plan_json.read(args.input)?, false)?
}

proc handle_repo_command(command: RepoCommand) [fs, net, process, env, time, error] {
  match command {
    LegacyCommand => return Err(types.PmError.Usage("internal: legacy command reached repository command handler"))
    RepoCheck(args) => command_repo_check(args)?
    RepoPlan(args) => command_repo_plan(args)?
    RepoShow(args) => command_repo_show(args)?
    RepoHelp(text) => print $text
  }
}

pure usage(message: Str) -> Error {
  types.PmError.Usage(f"usage: ${message}")
}

proc clear_directory_contents(root: Path) [fs, error] {
  if ! root.exists()? {
    return
  }

  var entries = [entry for entry in fs.walk(root) if entry.path != root]
  for entry in entries {
    if entry.kind != "dir" {
      fs.remove(entry.path, missing_ok: true)?
    }
  }

  let directories = entries
    |> where .kind == "dir"
    |> sort-by .path
  var index = directories.len()

  while index > 0 {
    index -= 1
    fs.remove(directories[index].path, missing_ok: true)?
  }
}

proc parse_pm_cli(argv: List[Str]) [error] -> Result[types.Cli] {
  let path_types = {root: "Path", work: "Path", out: "Path"}

  let commands = {
    smoke: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
      min_rest: 1,
    },
    install: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    remove: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    list: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    info: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    search: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    tree: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    outdated: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    upgrade: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    update: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    checksum: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    update_checksums: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    download: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    source_audit: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    refresh_index: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    auth: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    upload: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
    help_ext: {
      positionals: [
        "root",
        "work",
        "out",
      ],
      types: path_types,
      rest: "raw",
    },
  }

  let parsed: types.Cli = cli.commands(
    argv,
    rootless_default: "smoke",
    commands: commands,
    fallback_command: {
      positionals: [
        "action",
        "root",
        "work",
        "out",
      ],
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
  print "usage: pm COMMAND [ARG...]\n\nrepository planning:\n  repo check [--repo PATH]\n  repo plan [--repo PATH] (--all | --root PACKAGE...) --output PLAN [--target aarch64-linux-musl]\n  repo show PLAN\n\nlegacy execution commands:\n  build REPO_DIR PKGDIR...\n  world-plan PKGDIR... [--arch ARCH] [--build] [--upload] [--to-tranche N] [-j N|--jobs N]\n  build-install ROOT BUILD_ROOT WORK OUT PKGDIR...\n  build-set REPO_DIR PKGDIR...\n  build-upload-set REPO_DIR PKGDIR...\n  upload-set REPO_DIR\n  upload-repo-export REPO_DIR\n\nroot commands:\n  install [ROOT WORK OUT] PKG...\n  remove [ROOT WORK OUT] PKG...\n  list [ROOT WORK OUT]\n  info [ROOT WORK OUT] PKG...\n  tree [ROOT WORK OUT] [PKG...]\n  search [ROOT WORK OUT] QUERY [PKGDIR...]\n  outdated [ROOT WORK OUT] PKGDIR...\n  update [ROOT WORK OUT] PKGDIR...\n  upgrade [ROOT WORK OUT] PKGDIR...\n  checksum [ROOT WORK OUT] PKGDIR...\n  update-checksums [ROOT WORK OUT] PKGDIR...\n  download [ROOT WORK OUT] PKGDIR...\n  source-audit [ROOT WORK OUT] PKGDIR...\n  refresh-index [ROOT WORK OUT]\n  auth [ROOT WORK OUT] [TOKEN]\n  upload [ROOT WORK OUT] PKGDIR...\n  help-ext [ROOT WORK OUT]\n\nWhen run from inside this package repo, root commands default ROOT, WORK, and OUT\nto .root, .work, and .out at the repo root.\n\nworld-plan stores its staging repo under ~/.cache/laputa/world-<hash>, where\nthe hash covers the selected package set and arch. The state fingerprint covers\nselected PKGBUILD.xsh files so package edits invalidate an in-progress world.\n"
}

proc build_local_packages(
  ctx: types.PmContext,
  raw: List[Str],
  allow_installed_deps: Bool,
) [fs, net, process, env, time, error] -> Result[List[types.BuiltPackage]] {
  let dirs = util.paths_from_args(raw)?
  let packages = local.load_package_dirs(dirs)?
  let ordered = local.order_packages(ctx.root, packages, allow_installed_deps)?
  pm_build.build_packages(ctx, ordered)?
}

proc build_and_install_local_packages(
  ctx: types.PmContext,
  raw: List[Str],
  allow_installed_deps: Bool,
) [fs, net, process, env, time, error] {
  let built = build_local_packages(ctx, raw, allow_installed_deps)?
  install.install_built_packages(ctx, built)?
}

proc load_local_packages(raw: List[Str]) [fs, env, error] -> Result[List[types.Package]] {
  let dirs = util.paths_from_args(raw)?
  local.load_package_dirs(dirs)?
}

proc command_smoke(ctx: types.PmContext, raw: List[Str]) [fs, net, process, env, time, error] {
  let built = build_local_packages(ctx, raw, false)?
  install.install_built_packages(ctx, built)?
  install.remove_built_packages(ctx, built)?
}

proc command_install(ctx: types.PmContext, raw: List[Str]) [fs, net, process, env, time, error] {
  if remote.args_are_package_dirs(raw)? {
    build_and_install_local_packages(ctx, raw, true)?
  } else {
    install.install_remote_packages(ctx, raw)?
  }
}

proc command_search(ctx: types.PmContext, raw: List[Str]) [fs, env, error] {
  if raw.len() < 1 {
    return Err(usage("pm search ROOT WORK OUT QUERY [PKGDIR...]"))
  }

  let query = raw[0]
  var dirs = []
  var search_index = 1

  while search_index < raw.len() {
    dirs = dirs.push(fp"${raw[search_index]}")
    search_index += 1
  }

  let packages = local.load_package_dirs(dirs)?
  install.print_search_matches(ctx.root, query, packages)?
}

proc command_update(ctx: types.PmContext, raw: List[Str]) [fs, process, env, error] {
  let packages = load_local_packages(raw)?
  extensions.run_lifecycle_hooks("pre-update", "", ctx, "local")?
  local.write_local_index(ctx.out, packages)?
  extensions.run_lifecycle_hooks("post-update", "", ctx, "local")?
}

proc command_for_each_package(ctx: types.PmContext, raw: List[Str], action: Str) [fs, net, process, env, time, error] {
  let packages = load_local_packages(raw)?

  for pkg in packages {
    match action {
      "checksum" => local.print_package_checksums(ctx.work, pkg)?
      "update-checksums" => local.update_package_checksums(ctx.work, pkg)?
      "download" => local.download_package_sources(ctx.work, ctx.out, pkg)?
      "upload" => repo.upload_package(ctx, pkg)?
      _ => return Err(types.PmError.Usage(f"unknown package action ${action}"))
    }
  }
}

proc command_upgrade(ctx: types.PmContext, raw: List[Str]) [fs, net, process, env, time, error] {
  let packages = load_local_packages(raw)?
  let upgrade_names = local.collect_upgrade_names(ctx.root, packages)?

  if upgrade_names.len() > 0 {
    let selected = local.filter_packages_by_names(packages, upgrade_names)?
    let ordered = local.order_packages(ctx.root, selected, true)?
    let built = pm_build.build_packages(ctx, ordered)?
    install.install_built_packages(ctx, built)?
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
  var raw_args = []
  var build_i = 5

  while build_i < argv.len() {
    raw_args = raw_args.push(argv[build_i])
    build_i += 1
  }

  let packages = local.load_package_dirs(util.paths_from_args(raw_args)?)?
  let local_names = buildroot.local_package_names(packages)
  let root_ctx: types.PmContext = {command: "build-install", root, work, out}
  let build_ctx: types.PmContext = {command: "build-install", root: build_root, work, out}
  fs.mkdir(work)?
  let lock = fs.lock(fp"${work}/pm.lock")?
  defer fs.unlock(lock)?
  fs.mkdir(root)?
  fs.mkdir(build_root)?
  fs.mkdir(out)?
  buildroot.install_chroot_base(root_ctx, local_names, false)?
  buildroot.install_chroot_base(build_ctx, local_names, true)?
  buildroot.install_remote_dependency_set(
    root_ctx,
    buildroot.missing_dependency_names(root, packages, false, local_names)?,
  )?
  buildroot.install_remote_dependency_set(
    build_ctx,
    buildroot.missing_dependency_names(build_root, packages, true, local_names)?,
  )?
  let ordered = local.order_packages(build_root, packages, true)?

  for pkg in ordered {
    var built = []

    env {
      LAPUTA_ROOT = build_root.display()
      PATH = pm_env.build_path(build_root, env.get("PATH") ?? "")
    } {
      built = pm_build.build_packages(build_ctx, [pkg])?
    } ?

    install.install_built_packages(root_ctx, built)?

    if root.display() != build_root.display() {
      install.install_built_packages(build_ctx, built)?
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
  let root_ctx: types.PmContext = {command: "build-set", root, work, out}
  let build_ctx: types.PmContext = {command: "build-set", root: build_root, work, out}
  let upload_ctx: types.PmContext = {...build_ctx, command: "upload"}
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
  let reuse_set_roots = (env.get("XSH_PM_REUSE_SET_ROOTS") ?? "") == "1" and packages.len() == 1
  let root_pkg = packages[0]
  let root_pkgbuild = fp"${root_pkg.dir}/PKGBUILD.xsh"
  let root_fingerprint = bytes.from_text(f"""${util.target_arch()?}
${root_pkg.name}	${root_pkg.ver}	${root_pkg.rel}	${hash.sha256(root_pkgbuild)?.hex()}
""")
    .sha256()
    .hex()
  let root_fingerprint_path = fp"${work}/.set-roots-fingerprint"
  let roots_ready = reuse_set_roots and root.exists()? and build_root.exists()? and root_fingerprint_path.exists()? and root_fingerprint_path.read_text()?.trim() == root_fingerprint

  fs.mkdir(repo_dir)?
  if ! roots_ready {
    if reuse_set_roots {
      clear_directory_contents(root)?
      clear_directory_contents(build_root)?
    } else {
      fs.remove(root, missing_ok: true)?
      fs.remove(build_root, missing_ok: true)?
    }
  }

  fs.mkdir(root)?
  fs.mkdir(build_root)?
  fs.mkdir(work)?
  fs.mkdir(out)?
  fs.remove(util.remote_index_cache_path(out), missing_ok: true)?
  let lock = fs.lock(fp"${work}/pm.lock")?
  defer fs.unlock(lock)?
  let ordered = packages
  var built_names: Map[Bool] = {}
  var first_package = true

  for pkg in ordered {
    if ! (roots_ready and first_package) {
      if reuse_set_roots {
        clear_directory_contents(root)?
        clear_directory_contents(build_root)?
      } else {
        fs.remove(root, missing_ok: true)?
        fs.remove(build_root, missing_ok: true)?
      }

      fs.mkdir(root)?
      fs.mkdir(build_root)?
    }

    buildroot.install_chroot_base(root_ctx, local_names, false)?
    buildroot.install_chroot_base(build_ctx, local_names, true)?

    buildroot.install_remote_dependency_set(
      root_ctx,
      pm_world.missing_world_dependencies(root, pm_world.effective_world_dependencies(pkg, false), local_names, built_names)?,
    )?

    buildroot.install_remote_dependency_set(
      build_ctx,
      pm_world.missing_world_dependencies(build_root, pm_world.effective_world_dependencies(pkg, true), local_names, built_names)?,
    )?

    if reuse_set_roots and first_package {
      fs.write(root_fingerprint_path, root_fingerprint)?
    }

    var built = []

    env {
      LAPUTA_ROOT = build_root.display()
      PATH = pm_env.build_path(build_root, env.get("PATH") ?? "")
    } {
      built = pm_build.build_packages(build_ctx, [pkg])?
    } ?

    for item in built {
      index = repo.stage_built_package(repo_dir, upload_ctx, index, item)?
      built_names[item.pkg.name] = true

      first_package = false
    }

    json.write(index_path, index)?
    fs.remove(util.remote_index_cache_path(out), missing_ok: true)?
  }
}

proc build_upload_set_repo(argv: List[Str]) [fs, net, process, env, time, error] {
  build_set_repo(argv)?
  repo.upload_set_repo(argv)?
}

proc build_set_dependencies(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 3 {
    return Err(usage("pm build-set-deps REPO_DIR PKGDIR..."))
  }

  let repo_dir = path.absolute(fp"${argv[1]}")?
  let root = fp"${repo_dir}/.set-root"
  let build_root = fp"${repo_dir}/.set-build-root"
  let work = fp"${repo_dir}/.work"
  let out = fp"${repo_dir}/.out"
  let root_ctx: types.PmContext = {command: "build-set-deps", root, work, out}
  let build_ctx: types.PmContext = {command: "build-set-deps", root: build_root, work, out}
  var raw_args = []
  var build_i = 2

  while build_i < argv.len() {
    raw_args = raw_args.push(argv[build_i])
    build_i += 1
  }

  let packages = local.load_package_dirs(util.paths_from_args(raw_args)?)?
  let local_names = buildroot.local_package_names(packages)
  fs.mkdir(repo_dir)?
  fs.remove(root, missing_ok: true)?
  fs.remove(build_root, missing_ok: true)?
  fs.mkdir(root)?
  fs.mkdir(build_root)?
  fs.mkdir(work)?
  fs.mkdir(out)?
  let lock = fs.lock(fp"${work}/pm.lock")?
  defer fs.unlock(lock)?
  let started = time.now()

  buildroot.install_chroot_base(root_ctx, local_names, false)?
  buildroot.install_chroot_base(build_ctx, local_names, true)?
  buildroot.install_remote_dependency_set(
    root_ctx,
    buildroot.missing_dependency_names(root, packages, false, local_names)?,
  )?
  buildroot.install_remote_dependency_set(
    build_ctx,
    buildroot.missing_dependency_names(build_root, packages, true, local_names)?,
  )?
  let elapsed = time.now() - started
  print --flush "pm-dependencies-ready" $elapsed "ms" packages.len() "packages"
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
  command in [
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
  ]
}

pure command_requires_package_dirs(command: Str) -> Bool {
  command in ["outdated", "update", "upgrade", "checksum", "update-checksums", "download", "upload"]
}

pure arg_looks_like_path(value: Str) -> Bool {
  value.starts_with("/") or value.starts_with(".") or "/" in value
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
    if fs.exists(fp"${dir}/pm.xsh")? and fs.exists(fp"${dir}/repo")? {
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

  var expanded = [
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

proc handle_cli_command(parsed: types.Cli) [fs, net, process, env, time, error] {
  let command = parsed.command
  let ctx: types.PmContext = {command, root: parsed.root, work: parsed.work, out: parsed.out}
  fs.mkdir(ctx.work)?
  let lock = fs.lock(fp"${ctx.work}/pm.lock")?
  defer fs.unlock(lock)?
  fs.mkdir(ctx.root)?
  fs.mkdir(ctx.out)?

  match command {
    "smoke" => command_smoke(ctx, parsed.raw)?
    "install" => command_install(ctx, parsed.raw)?
    "remove" => install.remove_installed_packages(ctx, parsed.raw)?
    "list" => install.print_installed_list(ctx.root)?
    "info" => {
      for name in parsed.raw {
        install.print_package_info(ctx.root, name)?
      }
    }
    "tree" => install.print_dependency_tree(ctx.root, parsed.raw)?
    "search" => command_search(ctx, parsed.raw)?
    "outdated" => install.print_outdated(ctx.root, load_local_packages(parsed.raw)?)?
    "update" => command_update(ctx, parsed.raw)?
    "checksum" => command_for_each_package(ctx, parsed.raw, command)?
    "update-checksums" => command_for_each_package(ctx, parsed.raw, command)?
    "download" => command_for_each_package(ctx, parsed.raw, command)?
    "source-audit" => sources.audit_source_mirrors(ctx.out, load_local_packages(parsed.raw)?)?
    "refresh-index" => {
      extensions.run_lifecycle_hooks("pre-update", "", ctx, "remote")?
      let _ = remote.refresh_remote_index(ctx.out)?
      extensions.run_lifecycle_hooks("post-update", "", ctx, "remote")?
    }
    "auth" => remote.store_auth_token(ctx.root, parsed.raw)?
    "upload" => command_for_each_package(ctx, parsed.raw, command)?
    "upgrade" => command_upgrade(ctx, parsed.raw)?
    "help-ext" => extensions.print_extension_help()?
    _ => extensions.invoke_extension(command, ctx, parsed.raw)?
  }
}

## Exported PM declaration `run_pm_cli`.
export proc run_pm_cli(argv: List[Str]) [fs, net, process, env, time, error] {
  var a = argv

  if a.len() >= 1 and a[0] == "--" {
    var shifted = []
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

  let repo_command = parse_repo_command(a)?

  match repo_command {
    LegacyCommand => {}
    _ => {
      handle_repo_command(repo_command)?
      return
    }
  }

  if a.len() >= 1 and a[0] == "build" {
    repo.build_repo(a)?
    return
  }

  if a.len() >= 1 and a[0] == "build-install" {
    build_install_packages(a)?
    return
  }

  if a.len() >= 1 and a[0] == "world-plan" {
    pm_world.world_plan_repo(a)?
    return
  }

  if a.len() >= 1 and a[0] == "build-set" {
    build_set_repo(a)?
    return
  }

  if a.len() >= 1 and a[0] == "build-set-deps" {
    build_set_dependencies(a)?
    return
  }

  if a.len() >= 1 and a[0] == "build-prepared-package" {
    build_prepared_package_command(a)?
    return
  }

  if a.len() >= 1 and a[0] == "upload-set" {
    repo.upload_set_repo(a)?
    return
  }

  if a.len() >= 1 and a[0] == "build-upload-set" {
    build_upload_set_repo(a)?
    return
  }

  if a.len() >= 1 and a[0] == "upload-repo-export" {
    repo.upload_repo_export(a)?
    return
  }

  handle_cli_command(parse_pm_cli(default_root_command_argv(a)?)?)?
}
