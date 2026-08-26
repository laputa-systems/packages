##! Behavior coverage for explicit typed repository planning commands.
use pm.plan_json
use pm.types
use pm.catalog
use pm.generation
use pm.plan
use pm.policy

pure fixture(name: Str) -> Path {
  fp"tests/xsh/fixtures/${name}"
}

proc runner() [fs, process, env, error] -> Result[Path] {
  let configured = (env.get("XSH_HOST") ?? "").trim()

  if configured != "" {
    return path.absolute(fp"${configured}")?
  }

  process.which("xsh")?
}

proc module_root() [fs, error] -> Result[Path] {
  path.absolute(p".")?
}

proc copied_repository(ctx: TestContext, name: Str) [fs, error] -> Result[Path] {
  let root = test.temp_dir(ctx, name: name)?
  let _ = fs.copy_tree(fixture("graph-catalog/repo"), fp"${root}/repo", parents: true, overwrite: true)?
  fs.mkdir(fp"${root}/pm")?
  fs.copy(p"pm/proof.xsh", fp"${root}/pm/proof.xsh", overwrite: true)?
  root
}

pure cli_executor_identity() -> types.ExecutorIdentity {
  {
    format: "laputa-pm-executor-1",
    pm_sha256: "cli-pm",
    xsh_sha256: "cli-runners",
    core_sha256: "cli-core",
  }
}

pure cli_empty_remote() -> types.RemoteSnapshot {
  {target: types.target_aarch64(), index_sha256: "cli-empty-remote", packages: []}
}

proc published_generation_receipt(ctx: TestContext) [fs, env, error] -> Result[Path] {
  let repository = copied_repository(ctx, "root-inspect-receipt")?
  let build_value = plan.resolve(
    catalog.load(repository)?,
    cli_empty_remote(),
    policy.aarch64_docker(),
    ["app"],
    false,
    cli_executor_identity(),
  )?
  let overlay = test.temp_dir(ctx, name: "root-inspect-overlay")?
  fs.mkdir(fp"${overlay}/overlay")?
  let generation_value = generation.plan(build_value, ["app"], generation.overlay_digest(fp"${overlay}/overlay")?)?
  let receipt = test.temp_path(ctx, name: "published-generation.json")
  json.write(
    receipt,
    {
      format: "laputa-generation-1",
      generation_sha256: generation_value.generation_sha256,
      build_plan_sha256: generation_value.build_plan_sha256,
      profile: generation_value.profile.name,
      overlay_sha256: generation_value.profile.overlay_sha256,
      replacements: generation_value.profile.replacements,
      target: "aarch64-linux-musl",
      runtime_roots: generation_value.runtime_roots,
      artifacts: [
        {package_name: artifact.package_name, package_id: artifact.package_id, artifact_key: artifact.artifact_key}
        for artifact in generation_value.artifacts
      ],
      root_sha256: "0000000000000000000000000000000000000000000000000000000000000000",
    },
  )?
  receipt
}

proc pm_output(args: List[Str]) [fs, process, env, error] -> Result[Str] {
  let xsh = runner()?
  let modules = module_root()?
  return run.text XSH_HOST=$xsh XSH_MODULE_PATH=$modules XSH_PM_OFFLINE=1 $xsh pm.xsh -- @args ?
}

proc pm_status(args: List[Str], err: Path) [fs, process, env, error] -> Result[Status] {
  let xsh = runner()?
  let modules = module_root()?
  return run.status XSH_HOST=$xsh XSH_MODULE_PATH=$modules XSH_PM_OFFLINE=1 $xsh pm.xsh -- @args 2> $err
}

proc test_repo_help_is_explicit(ctx: TestContext) [fs, process, env, error] {
  let top = pm_output(["--help"])?
  let repository = pm_output(["repo", "--help"])?
  let plan = pm_output(["repo", "plan", "--help"])?

  test.contains(top, "repo plan [--repo PATH] (--all | --root PACKAGE...) --target aarch64-linux-musl --output PLAN")?
  test.contains(top, "repo build PLAN --store STORE")?
  test.contains(top, "root compose PLAN --store STORE --runtime-root PACKAGE... --output GENERATION")?
  test.eq(top.contains("world-plan"), false)?
  test.contains(repository, "checksum [--repo PATH] PACKAGE...")?
  test.contains(plan, "repo plan [--repo PATH] (--all | --root PACKAGE...)")?
}

proc test_final_cli_rejects_removed_legacy_command(ctx: TestContext) [fs, process, env, error] {
  let err = test.temp_path(ctx, name: "legacy-command.err")
  let status = pm_status(["build-set", "repo"], err)?

  test.eq(status.ok, false)?
  test.contains(err.read_text()?, "unknown pm command build-set")?
}

proc test_store_verify_accepts_explicit_empty_store(ctx: TestContext) [fs, process, env, error] {
  let store_root = test.temp_dir(ctx, name: "empty-store")?
  let output = pm_output(["store", "verify", "--store", store_root.display()])?

  test.contains(output, "store verify 0 artifacts")?
}

proc test_root_inspect_accepts_published_generation_receipt_file(ctx: TestContext) [fs, process, env, error] {
  let receipt = published_generation_receipt(ctx)?
  let output = pm_output(["root", "inspect", receipt.display()])?

  test.contains(output, "root inspect")?
  test.contains(output, "runtime-roots app")?
  test.contains(output, "artifacts 2")?
}

proc test_repo_check_validates_catalog(ctx: TestContext) [fs, process, env, error] {
  let root = copied_repository(ctx, "repo-check")?
  let output = pm_output(["repo", "check", "--repo", root.display()])?
  let discovered = pm_output(["repo", "check"])?
  test.contains(output, "repo check 4 packages 3 edges")?
  test.contains(discovered, "repo check")?
}

proc test_repo_plan_requires_explicit_selection_output_and_target(ctx: TestContext) [fs, process, env, error] {
  let root = copied_repository(ctx, "repo-arguments")?
  let err = test.temp_path(ctx, name: "repo-arguments.err")
  let output = fp"${root}/out/plan.json"

  let missing_selection = pm_status(["repo", "plan", "--repo", root.display(), "--output", output.display()], err)?
  test.eq(missing_selection.ok, false)?
  test.contains(err.read_text()?, "requires exactly one of --all or one-or-more --root")?

  let both = pm_status(["repo", "plan", "--repo", root.display(), "--all", "--root", "app", "--output", output.display()], err)?
  test.eq(both.ok, false)?
  test.contains(err.read_text()?, "requires exactly one of --all or one-or-more --root")?

  let missing_output = pm_status(["repo", "plan", "--repo", root.display(), "--root", "app"], err)?
  test.eq(missing_output.ok, false)?
  test.contains(err.read_text()?, "missing required argument --output")?

  let unsupported_target = pm_status(["repo", "plan", "--repo", root.display(), "--root", "app", "--output", output.display(), "--target", "x86_64-linux-musl"], err)?
  test.eq(unsupported_target.ok, false)?
  test.contains(err.read_text()?, "unsupported target x86_64-linux-musl")?
}

proc test_repo_plan_does_not_infer_path_arguments(ctx: TestContext) [fs, process, env, error] {
  let root = copied_repository(ctx, "repo-no-inference")?
  let err = test.temp_path(ctx, name: "repo-no-inference.err")
  let package_like = fp"${root}/looks-like-package"
  fs.mkdir(package_like)?
  fs.write(fp"${package_like}/PKGBUILD.xsh", "not a command argument\n")?

  let status = pm_status(
    ["repo", "plan", "--repo", root.display(), "--all", "--output", fp"${root}/out/plan.json".display(), package_like.display()],
    err,
  )?

  test.eq(status.ok, false)?
  test.contains(err.read_text()?, "unexpected positional argument")?
}

proc test_repo_plan_writes_and_show_renders_verified_fields(ctx: TestContext) [fs, process, env, error] {
  let root = copied_repository(ctx, "repo-plan")?
  let output = fp"${root}/out/plan.json"
  let planned = pm_output(["repo", "plan", "--repo", root.display(), "--root", "app", "--output", output.display()])?
  let value = plan_json.read(output)?
  let shown = pm_output(["repo", "show", output.display()])?

  test.ok(output.exists()?)?
  test.eq(value.target, types.target_aarch64())?
  test.contains(planned, "level 1 app build")?
  test.contains(shown, "level 1 app build")?
  test.contains(shown, "new package")?
  test.contains(shown, value.nodes[0].artifact_key)?
}

proc test_repo_show_rejects_corrupt_plan(ctx: TestContext) [fs, process, env, error] {
  let root = copied_repository(ctx, "repo-corrupt")?
  let output = fp"${root}/out/plan.json"
  let _ = pm_output(["repo", "plan", "--repo", root.display(), "--root", "app", "--output", output.display()])?
  let value = plan_json.read(output)?
  fs.write(output, output.read_text()?.replace(value.plan_sha256, "corrupt-plan-digest"))?
  let err = test.temp_path(ctx, name: "repo-corrupt.err")
  let status = pm_status(["repo", "show", output.display()], err)?

  test.eq(status.ok, false)?
  test.contains(err.read_text()?, "build plan digest does not match")?
}
