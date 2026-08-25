##! Explicit typed command boundary for immutable package planning, execution, publication, and generation composition.
use catalog
use execute as pm_execute
use fingerprint as pm_fingerprint
use generation
use graph
use local
use plan as pm_plan
use plan_json as pm_plan_json
use policy
use recipe
use remote
use repo
use sources
use store
use types
use util

type RepoCheckArgs = {repo: Path}
type RepoPlanArgs = {repo: Path, all: Bool, roots: List[Str], target: Str, output: Path}
type RepoShowArgs = {input: Path}
type RepoBuildArgs = {input: Path, store: Path, jobs: Int}
type RepoPublishArgs = {input: Path, store: Path}
type RepoPackagesArgs = {repo: Path, packages: List[Str]}
type RootComposeArgs = {input: Path, store: Path, runtime_roots: List[Str], output: Path}
type RootInspectArgs = {input: Path}
type StoreVerifyArgs = {store: Path}

type PmCommand = Help(Str) | RepoCheck(RepoCheckArgs) | RepoPlan(RepoPlanArgs) | RepoShow(RepoShowArgs) | RepoBuild(RepoBuildArgs) | RepoPublish(RepoPublishArgs) | RepoChecksum(RepoPackagesArgs) | RepoUpdateChecksums(RepoPackagesArgs) | RepoSourceAudit(RepoPackagesArgs) | RootCompose(RootComposeArgs) | RootInspect(RootInspectArgs) | StoreVerify(StoreVerifyArgs)

type RepoCheckOptions = {repo: Str}
type RepoPlanOptions = {repo: Str, all: Bool, roots: List[Str], target: Str, output: Path}
type RepoShowOptions = {input: Path}
type RepoBuildOptions = {input: Path, store: Path, jobs: Int}
type RepoPublishOptions = {input: Path, store: Path}
type RepoPackagesOptions = {repo: Str, packages: List[Str]}
type RootComposeOptions = {input: Path, store: Path, runtime_roots: List[Str], output: Path}
type RootInspectOptions = {input: Path}
type StoreVerifyOptions = {store: Path}

pure help_text() -> Str {
  """usage: pm COMMAND [OPTIONS]

repository commands:
  repo check [--repo PATH]
  repo plan [--repo PATH] (--all | --root PACKAGE...) --target aarch64-linux-musl --output PLAN
  repo show PLAN
  repo build PLAN --store STORE [-j N|--jobs N]
  repo publish PLAN --store STORE
  repo checksum [--repo PATH] PACKAGE...
  repo update-checksums [--repo PATH] PACKAGE...
  repo source-audit [--repo PATH] PACKAGE...

root commands:
  root compose PLAN --store STORE --runtime-root PACKAGE... --output GENERATION
  root inspect GENERATION

store commands:
  store verify --store STORE
"""
}

pure repo_help_text() -> Str {
  """usage: pm repo COMMAND [OPTIONS]

  check [--repo PATH]
  plan [--repo PATH] (--all | --root PACKAGE...) --target aarch64-linux-musl --output PLAN
  show PLAN
  build PLAN --store STORE [-j N|--jobs N]
  publish PLAN --store STORE
  checksum [--repo PATH] PACKAGE...
  update-checksums [--repo PATH] PACKAGE...
  source-audit [--repo PATH] PACKAGE...
"""
}

pure root_help_text() -> Str {
  """usage: pm root COMMAND [OPTIONS]

  compose PLAN --store STORE --runtime-root PACKAGE... --output GENERATION
  inspect GENERATION
"""
}

pure store_help_text() -> Str {
  """usage: pm store verify --store STORE
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

# Parent discovery is intentionally restricted to a complete package repository.
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

proc repo_default_root() [fs, error] -> Result[Path] {
  let root = current_pm_repo_root()?

  if root.display() == "" {
    return Err(types.PmError.Usage("pm repo requires --repo outside a package repository"))
  }

  root
}

proc execution_repo_root() [fs, error] -> Result[Path] {
  let root = current_pm_repo_root()?

  if root.display() == "" {
    return Err(types.PmError.Usage("pm repo build requires running inside a package repository"))
  }

  root
}

proc resolve_repo_root(raw: Str) [fs, error] -> Result[Path] {
  if raw == "" {
    return repo_default_root()?
  }

  path.absolute(fp"${raw}")?
}

proc parse_repo_packages(args: List[Str], command: Str) [fs, error] -> Result[RepoPackagesArgs] {
  var parsed: RepoPackagesOptions = {repo: "", packages: []}

  match cli.parse(
    args,
    {
      repo: {form: "--repo PATH", default: ""},
      packages: {form: "...PACKAGE"},
    },
    command,
  ) {
    Ok(value) => parsed = value
    Err(problem) => return Err(problem)
  }

  if parsed.packages.len() == 0 {
    return Err(types.PmError.Usage(f"${command} requires one-or-more PACKAGE arguments"))
  }

  {repo: resolve_repo_root(parsed.repo)?, packages: parsed.packages}
}

proc parse_repo_command(argv: List[Str]) [fs, error] -> Result[PmCommand] {
  if argv.len() == 1 or argv[1] in ["-h", "--help", "help"] {
    return Help(repo_help_text())
  }

  let action = argv[1]
  let args = tail_after(argv, 2)

  if action not in ["check", "plan", "show", "build", "publish", "checksum", "update-checksums", "source-audit"] {
    return Err(types.PmError.Usage(f"unknown pm repo command ${action}"))
  }

  if args.len() == 1 and args[0] in ["-h", "--help", "help"] {
    return Help(repo_help_text())
  }

  match action {
    "check" => {
      var parsed: RepoCheckOptions = {repo: ""}
      match cli.parse(args, {repo: {form: "--repo PATH", default: ""}}, "pm repo check") {
        Ok(value) => parsed = value
        Err(problem) => return Err(problem)
      }
      return RepoCheck({repo: resolve_repo_root(parsed.repo)?})
    }
    "plan" => {
      var parsed: RepoPlanOptions = {repo: "", all: false, roots: [], target: "aarch64-linux-musl", output: p""}
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
        return Err(types.PmError.Usage("pm repo plan requires exactly one of --all or one-or-more --root"))
      }

      let _ = types.parse_target(parsed.target)?
      return RepoPlan({repo: resolve_repo_root(parsed.repo)?, all: parsed.all, roots: parsed.roots, target: parsed.target, output: parsed.output})
    }
    "show" => {
      var parsed: RepoShowOptions = {input: p""}
      match cli.parse(args, {input: {form: "PLAN", kind: "Path", required: true}}, "pm repo show") {
        Ok(value) => parsed = value
        Err(problem) => return Err(problem)
      }
      return RepoShow({input: parsed.input})
    }
    "build" => {
      var parsed: RepoBuildOptions = {input: p"", store: p"", jobs: cpu.count()}
      match cli.parse(
        args,
        {
          input: {form: "PLAN", kind: "Path", required: true},
          store: {form: "--store STORE", kind: "Path", required: true},
          jobs: {form: "-j --jobs N", kind: "Int", default: cpu.count(), min: 1},
        },
        "pm repo build",
      ) {
        Ok(value) => parsed = value
        Err(problem) => return Err(problem)
      }
      return RepoBuild({input: parsed.input, store: parsed.store, jobs: parsed.jobs})
    }
    "publish" => {
      var parsed: RepoPublishOptions = {input: p"", store: p""}
      match cli.parse(
        args,
        {
          input: {form: "PLAN", kind: "Path", required: true},
          store: {form: "--store STORE", kind: "Path", required: true},
        },
        "pm repo publish",
      ) {
        Ok(value) => parsed = value
        Err(problem) => return Err(problem)
      }
      return RepoPublish({input: parsed.input, store: parsed.store})
    }
    "checksum" => return RepoChecksum(parse_repo_packages(args, "pm repo checksum")?)
    "update-checksums" => return RepoUpdateChecksums(parse_repo_packages(args, "pm repo update-checksums")?)
    "source-audit" => return RepoSourceAudit(parse_repo_packages(args, "pm repo source-audit")?)
    _ => return Err(types.PmError.Usage(f"unknown pm repo command ${action}"))
  }
}

proc parse_root_command(argv: List[Str]) [error] -> Result[PmCommand] {
  if argv.len() == 1 or argv[1] in ["-h", "--help", "help"] {
    return Help(root_help_text())
  }

  let action = argv[1]
  let args = tail_after(argv, 2)

  if action not in ["compose", "inspect"] {
    return Err(types.PmError.Usage(f"unknown pm root command ${action}"))
  }

  if args.len() == 1 and args[0] in ["-h", "--help", "help"] {
    return Help(root_help_text())
  }

  if action == "compose" {
    var parsed: RootComposeOptions = {input: p"", store: p"", runtime_roots: [], output: p""}
    match cli.parse(
      args,
      {
        input: {form: "PLAN", kind: "Path", required: true},
        store: {form: "--store STORE", kind: "Path", required: true},
        runtime_roots: {form: "--runtime-root PACKAGE", repeated: true},
        output: {form: "--output GENERATION", kind: "Path", required: true},
      },
      "pm root compose",
    ) {
      Ok(value) => parsed = value
      Err(problem) => return Err(problem)
    }

    if parsed.runtime_roots.len() == 0 {
      return Err(types.PmError.Usage("pm root compose requires one-or-more --runtime-root PACKAGE"))
    }

    return RootCompose({input: parsed.input, store: parsed.store, runtime_roots: parsed.runtime_roots, output: parsed.output})
  }

  var parsed: RootInspectOptions = {input: p""}
  match cli.parse(args, {input: {form: "GENERATION", kind: "Path", required: true}}, "pm root inspect") {
    Ok(value) => parsed = value
    Err(problem) => return Err(problem)
  }
  RootInspect({input: parsed.input})
}

proc parse_store_command(argv: List[Str]) [error] -> Result[PmCommand] {
  if argv.len() == 1 or argv[1] in ["-h", "--help", "help"] {
    return Help(store_help_text())
  }

  if argv[1] != "verify" {
    return Err(types.PmError.Usage(f"unknown pm store command ${argv[1]}"))
  }

  var parsed: StoreVerifyOptions = {store: p""}
  match cli.parse(tail_after(argv, 2), {store: {form: "--store STORE", kind: "Path", required: true}}, "pm store verify") {
    Ok(value) => parsed = value
    Err(problem) => return Err(problem)
  }
  StoreVerify({store: parsed.store})
}

proc parse_command(argv: List[Str]) [fs, error] -> Result[PmCommand] {
  if argv.len() == 0 or argv[0] in ["-h", "--help", "help"] {
    return Help(help_text())
  }

  match argv[0] {
    "repo" => parse_repo_command(argv)?
    "root" => parse_root_command(argv)?
    "store" => parse_store_command(argv)?
    _ => return Err(types.PmError.Usage(f"unknown pm command ${argv[0]}"))
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

proc remote_snapshot_for_plan(cache_root: Path) [fs, net, env, time, error] -> Result[types.RemoteSnapshot] {
  var index: List[types.RemotePackage] = []
  let cache = util.remote_index_cache_path(cache_root)
  let offline = (env.get("XSH_PM_OFFLINE") ?? "") == "1"

  if cache.exists()? {
    index = remote.load_cached_remote_index(cache_root)?
  } else if ! offline {
    let urls = remote.load_repo_urls()?

    for endpoint in [urls.public_repo, urls.repo] {
      continue when endpoint == ""
      let fetched = remote.load_remote_index_from_repo(endpoint, cache_root)?

      for entry in fetched {
        index = remote.upsert_remote_package(index, entry)?
      }
    }

    remote.write_remote_index_cache(cache_root, index)?
  }

  let index_sha256 = if cache.exists()? { hash.sha256(cache)?.hex() } else { bytes.from_text("[]\n").sha256().hex() }
  var packages: List[types.RemotePlanArtifact] = []

  for entry in index {
    continue unless entry.arch == "aarch64"
    packages = packages.push(remote.plan_artifact_from_package(entry)?)
  }

  {target: types.Aarch64LinuxMusl, index_sha256, packages}
}

proc selected_packages(repo_root: Path, names: List[Str]) [fs, env, error] -> Result[List[types.Package]] {
  let value = catalog.load(repo_root)?
  let by_name = catalog.package_map(value)
  var selected: List[types.Package] = []
  var seen: Map[Bool] = {}

  for name in names {
    if seen.has(name) {
      return Err(types.PmError.Usage(f"package ${name} was selected more than once"))
    }

    if ! by_name.has(name) {
      return Err(types.PmError.MissingDependency(f"package ${name} is not in ${repo_root.display()}"))
    }

    let listed: types.Package = by_name.get(name)?
    selected = selected.push(recipe.load_package(fp"${repo_root}/${listed.dir}")?)
    seen[name] = true
  }

  selected
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

  let cache_handle = fs.tempdir()?
  defer fs.close_root(cache_handle)?
  let cache_root = fs.root_path(cache_handle)?
  let value = pm_plan.resolve(
    catalog.load(args.repo)?,
    remote_snapshot_for_plan(cache_root)?,
    policy_value,
    args.roots,
    args.all,
    cli_executor_identity(args.repo)?,
  )?

  # The durable DTO and atomic write are kept behind `write_plan` while the release
  # native-test runner cannot encode a direct reachable call to `plan_json.write`.
  pm_plan_json.write_plan(args.output, value)?
  print pm_plan.render(value, false)?
}

proc command_repo_show(args: RepoShowArgs) [fs, error] {
  print pm_plan.render(pm_plan_json.read(args.input)?, false)?
}

proc command_repo_build(args: RepoBuildArgs) [fs, net, process, env, time, error] {
  let value = pm_plan_json.read(args.input)?
  let urls = remote.load_repo_urls()?
  let result = pm_execute.build_plan(value, execution_repo_root()?, args.store, urls.repo, args.jobs)?
  print "repo" "build" $result.plan_sha256 $result.artifacts.len() "artifacts"
}

proc command_repo_publish(args: RepoPublishArgs) [fs, net, env, time, error] {
  let value = pm_plan_json.read(args.input)?
  let snapshot = repo.snapshot(value, args.store)?
  let urls = remote.require_repo_url()?
  let work_handle = fs.tempdir()?
  defer fs.close_root(work_handle)?
  let token = (env.get("LAPUTA_TOKEN") ?? "").trim()
  repo.publish(snapshot, urls.repo, token, fs.root_path(work_handle)?)?
  print "repo" "publish" $value.plan_sha256 $snapshot.packages.len() "artifacts"
}

proc command_repo_checksums(args: RepoPackagesArgs, update: Bool) [fs, net, process, env, time, error] {
  let work_handle = fs.tempdir()?
  defer fs.close_root(work_handle)?
  let work = fs.root_path(work_handle)?

  for pkg in selected_packages(args.repo, args.packages)? {
    if update {
      local.update_package_checksums(work, pkg)?
    } else {
      local.print_package_checksums(work, pkg)?
    }
  }
}

proc command_repo_source_audit(args: RepoPackagesArgs) [fs, env, error] {
  # Source mirrors remain an explicit repository cache; this command neither resolves
  # packages nor mutates a root generation.
  sources.audit_source_mirrors(fp"${args.repo}/.out", selected_packages(args.repo, args.packages)?)?
}

proc command_root_compose(args: RootComposeArgs) [fs, error] {
  let value = pm_plan_json.read(args.input)?
  let overlay_handle = fs.tempdir()?
  defer fs.close_root(overlay_handle)?
  let overlay = fs.root_path(overlay_handle)?
  let generation_plan = generation.plan(value, args.runtime_roots, generation.overlay_digest(overlay)?)?
  let receipt = generation.compose(generation_plan, args.store, args.output, overlay)?
  print "root" "compose" $receipt.generation_sha256 $receipt.root_sha256
}

proc command_root_inspect(args: RootInspectArgs) [fs, error] {
  let receipt = generation.read_generation_receipt(args.input)?
  print "root" "inspect" $receipt.generation_sha256 $receipt.root_sha256
  print "runtime-roots" receipt.runtime_roots.join(" ")
  print "artifacts" receipt.artifacts.len()
}

proc command_store_verify(args: StoreVerifyArgs) [fs, error] {
  let receipts = store.verify_all(args.store)?
  print "store" "verify" receipts.len() "artifacts"
}

proc handle(command: PmCommand) [fs, net, process, env, time, error] {
  match command {
    Help(text) => print $text
    RepoCheck(args) => command_repo_check(args)?
    RepoPlan(args) => command_repo_plan(args)?
    RepoShow(args) => command_repo_show(args)?
    RepoBuild(args) => command_repo_build(args)?
    RepoPublish(args) => command_repo_publish(args)?
    RepoChecksum(args) => command_repo_checksums(args, false)?
    RepoUpdateChecksums(args) => command_repo_checksums(args, true)?
    RepoSourceAudit(args) => command_repo_source_audit(args)?
    RootCompose(args) => command_root_compose(args)?
    RootInspect(args) => command_root_inspect(args)?
    StoreVerify(args) => command_store_verify(args)?
  }
}

## Parses only the final explicit PM command surface; there are no extension or legacy fallbacks.
export proc run_pm_cli(argv: List[Str]) [fs, net, process, env, time, error] {
  let args = if argv.len() > 0 and argv[0] == "--" { tail_after(argv, 1) } else { argv }
  handle(parse_command(args)?)?
}
