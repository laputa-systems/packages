##! Behavior coverage for explicit typed repository planning commands.
use pm.plan_json
use pm.types
use pm.catalog
use pm.generation
use pm.plan
use pm.policy
use pm.store

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

test test_repo_help_is_explicit [fs, process, env, error] { |ctx|
  let top = pm_output(["--help"])?
  let repository = pm_output(["repo", "--help"])?
  let plan = pm_output(["repo", "plan", "--help"])?

  "repo plan [--repo PATH] (--all | --root PACKAGE...) [--target TARGET] --output PLAN" in top
  "x86_64-linux-musl (native Linux runner)" in plan
  "repo build PLAN --store STORE" in top
  "root compose PLAN --store STORE --runtime-root PACKAGE... --output GENERATION" in top
  "world-plan" not in top
  "checksum [--repo PATH] PACKAGE..." in repository
  "repo plan [--repo PATH] (--all | --root PACKAGE...)" in plan
}

test test_final_cli_rejects_removed_legacy_command [fs, process, env, error] { |ctx|
  let err = test.temp_path(ctx, name: "legacy-command.err")
  let status = pm_status(["build-set", "repo"], err)?

  test.eq(status.ok, false)?
  let observed_output_1 = err.read_text()?
  "unknown pm command build-set" in observed_output_1
}

test test_store_verify_accepts_explicit_empty_store [fs, process, env, error] { |ctx|
  let store_root = test.temp_dir(ctx, name: "empty-store")?
  let output = pm_output(["store", "verify", "--store", store_root.display()])?

  "store verify 0 artifacts" in output
}

test test_store_extract_copies_only_manifest_declared_file_from_saved_plan [fs, process, env, error] { |ctx|
  let repository = copied_repository(ctx, "store-extract-repository")?
  let build_plan = plan.resolve(
    catalog.load(repository)?,
    cli_empty_remote(),
    policy.aarch64_docker(),
    ["app"],
    false,
    cli_executor_identity(),
  )?
  let selected = [node for node in build_plan.nodes if node.name == "runtime-lib"][0]
  let plan_path = test.temp_path(ctx, name: "store-extract-plan.json")
  plan_json.write_plan(plan_path, build_plan)?
  let stage = test.temp_dir(ctx, name: "store-extract-stage")?
  let contents = fp"${stage}/contents"
  let kernel = fp"${contents}/boot/vmlinuz"
  fs.mkdir(kernel.parent)?
  fs.write(kernel, "kernel payload\n")?
  let payload = fp"${stage}/payload.tar.gz"
  archive.tar_create(payload, contents, [p"."], compression: "gz")?
  let metadata = fp"${stage}/metadata.json"
  json.write(metadata, {
    name: selected.name,
    ver: selected.ver,
    rel: selected.rel,
    package_kind: "payload",
    files: [{path: "boot/vmlinuz", kind: "file", mode: 0o644, sha256: bytes.from_text("kernel payload\n").sha256().hex(), target: ""}],
  })?
  let proof = fp"${stage}/proof.json"
  fs.write(proof, "proof\n")?
  let store_root = test.temp_dir(ctx, name: "store-extract-store")?
  let _ = store.commit(types.target_aarch64(), store_root, selected, {payload, metadata, proof, executor_sha256: plan.executor_fingerprint(build_plan.executor)?})?
  let output = test.temp_path(ctx, name: "extracted-vmlinuz")

  let _ = pm_output([
    "store", "extract", plan_path.display(), "--store", store_root.display(),
    "--package", selected.name, "--path", "boot/vmlinuz", "--output", output.display(),
  ])?
  test.eq(output.read_text()?, "kernel payload\n")?

  fs.write(output, "previous output\n")?
  let error_output = test.temp_path(ctx, name: "store-extract-error.txt")
  let missing = pm_status([
    "store", "extract", plan_path.display(), "--store", store_root.display(),
    "--package", selected.name, "--path", "boot/missing", "--output", output.display(),
  ], error_output)?
  test.eq(missing.ok, false)?
  let observed_output_2 = error_output.read_text()?
  "artifact metadata does not declare boot/missing" in observed_output_2
  test.eq(output.read_text()?, "previous output\n")?

  let traversal = pm_status([
    "store", "extract", plan_path.display(), "--store", store_root.display(),
    "--package", selected.name, "--path", "../outside", "--output", output.display(),
  ], error_output)?
  test.eq(traversal.ok, false)?
  let observed_output_3 = error_output.read_text()?
  "store extraction path must stay relative" in observed_output_3
  test.eq(output.read_text()?, "previous output\n")?
}

test test_root_inspect_accepts_published_generation_receipt_file [fs, process, env, error] { |ctx|
  let receipt = published_generation_receipt(ctx)?
  let output = pm_output(["root", "inspect", receipt.display()])?

  "root inspect" in output
  "runtime-roots app" in output
  "artifacts 2" in output
}

test test_repo_check_validates_catalog [fs, process, env, error] { |ctx|
  let root = copied_repository(ctx, "repo-check")?
  let output = pm_output(["repo", "check", "--repo", root.display()])?
  let discovered = pm_output(["repo", "check"])?
  "repo check 4 packages 3 edges" in output
  "repo check" in discovered
}

test test_repo_plan_requires_explicit_selection_output_and_target [fs, process, env, error] { |ctx|
  let root = copied_repository(ctx, "repo-arguments")?
  let err = test.temp_path(ctx, name: "repo-arguments.err")
  let output = fp"${root}/out/plan.json"

  let missing_selection = pm_status(["repo", "plan", "--repo", root.display(), "--output", output.display()], err)?
  test.eq(missing_selection.ok, false)?
  let observed_output_4 = err.read_text()?
  "requires exactly one of --all or one-or-more --root" in observed_output_4

  let both = pm_status(["repo", "plan", "--repo", root.display(), "--all", "--root", "app", "--output", output.display()], err)?
  test.eq(both.ok, false)?
  let observed_output_5 = err.read_text()?
  "requires exactly one of --all or one-or-more --root" in observed_output_5

  let missing_output = pm_status(["repo", "plan", "--repo", root.display(), "--root", "app"], err)?
  test.eq(missing_output.ok, false)?
  let observed_output_6 = err.read_text()?
  "missing required argument --output" in observed_output_6

  let unsupported_target = pm_status(["repo", "plan", "--repo", root.display(), "--root", "app", "--output", output.display(), "--target", "sparc64-linux-musl"], err)?
  test.eq(unsupported_target.ok, false)?
  let observed_output_7 = err.read_text()?
  "unsupported target sparc64-linux-musl" in observed_output_7
}

test test_repo_plan_does_not_infer_path_arguments [fs, process, env, error] { |ctx|
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
  let observed_output_8 = err.read_text()?
  "unexpected positional argument" in observed_output_8
}

test test_repo_plan_writes_and_show_renders_verified_fields [fs, process, env, error] { |ctx|
  let root = copied_repository(ctx, "repo-plan")?
  let output = fp"${root}/out/plan.json"
  let planned = pm_output(["repo", "plan", "--repo", root.display(), "--root", "app", "--output", output.display()])?
  let value = plan_json.read(output)?
  let shown = pm_output(["repo", "show", output.display()])?

  test.ok(output.exists()?)?
  test.eq(value.target, types.target_aarch64())?
  "level 1 app build" in planned
  "level 1 app build" in shown
  "new package" in shown
  value.nodes[0].artifact_key in shown
}

test test_repo_plan_records_x86_64_target_and_distinct_artifact_keys [fs, process, env, error] { |ctx|
  let root = copied_repository(ctx, "repo-x86-plan")?
  let arm_output = fp"${root}/out/arm-plan.json"
  let x86_output = fp"${root}/out/x86-plan.json"
  let _ = pm_output(["repo", "plan", "--repo", root.display(), "--root", "app", "--output", arm_output.display()])?
  let _ = pm_output(["repo", "plan", "--repo", root.display(), "--root", "app", "--target", "x86_64-linux-musl", "--output", x86_output.display()])?
  let arm = plan_json.read(arm_output)?
  let x86 = plan_json.read(x86_output)?

  test.eq(types.target_text(x86.target), "x86_64-linux-musl")?
  test.eq(arm.nodes.len(), x86.nodes.len())?
  test.eq(arm.nodes[0].artifact_key == x86.nodes[0].artifact_key, false)?

  if system.uname()?.sysname == "Linux" and system.uname()?.machine == "x86_64" {
    return
  }

  let store = fp"${root}/store"
  let err = test.temp_path(ctx, name: "repo-x86-build.err")
  let build_status = pm_status(["repo", "build", x86_output.display(), "--store", store.display()], err)?
  test.eq(build_status.ok, false)?
  let observed_output_9 = err.read_text()?
  "repo build requires a native Linux x86_64 runner" in observed_output_9
  test.eq(store.exists()?, false)?
}

test test_repo_show_rejects_corrupt_plan [fs, process, env, error] { |ctx|
  let root = copied_repository(ctx, "repo-corrupt")?
  let output = fp"${root}/out/plan.json"
  let _ = pm_output(["repo", "plan", "--repo", root.display(), "--root", "app", "--output", output.display()])?
  let value = plan_json.read(output)?
  fs.write(output, output.read_text()?.replace(value.plan_sha256, "corrupt-plan-digest"))?
  let err = test.temp_path(ctx, name: "repo-corrupt.err")
  let status = pm_status(["repo", "show", output.display()], err)?

  test.eq(status.ok, false)?
  let observed_output_10 = err.read_text()?
  "build plan digest does not match" in observed_output_10
}
