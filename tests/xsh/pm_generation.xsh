##! Behavior coverage for runtime-pure system generation plans and verified overlay composition.
use pm.catalog
use pm.generation
use pm.plan
use pm.policy
use pm.store
use pm.types

pure fixture(name: Str) -> Path {
  fp"tests/xsh/fixtures/${name}"
}

pure generation_executor_identity() -> types.ExecutorIdentity {
  {
    format: "laputa-pm-executor-1",
    pm_sha256: "generation-pm",
    xsh_sha256: "generation-runners",
    core_sha256: "generation-core",
  }
}

pure generation_empty_remote() -> types.RemoteSnapshot {
  {target: types.Aarch64LinuxMusl, index_sha256: "generation-empty-remote", packages: []}
}

pure test_generation_sha256(value: Str) -> Str {
  bytes.from_text(value).sha256().hex()
}

proc copied_generation_repository(ctx: TestContext, name: Str) [fs, env, error] -> Result[Path] {
  let root = test.temp_dir(ctx, name: name)?
  let _ = fs.copy_tree(fixture("graph-catalog/repo"), fp"${root}/repo", parents: true, overwrite: true)?
  fs.mkdir(fp"${root}/pm")?
  fs.copy(p"pm/proof.xsh", fp"${root}/pm/proof.xsh", overwrite: true)?
  root
}

proc generation_build_plan(ctx: TestContext, name: Str) [fs, env, error] -> Result[types.BuildPlan] {
  let repo_root = copied_generation_repository(ctx, name)?
  plan.resolve(
    catalog.load(repo_root)?,
    generation_empty_remote(),
    policy.aarch64_docker(),
    ["app"],
    false,
    generation_executor_identity(),
  )?
}

proc stage_generation_artifacts(ctx: TestContext, value: types.BuildPlan, store_root: Path) [fs, error] {
  let executor_sha256 = plan.executor_fingerprint(value.executor)?

  for node in value.nodes {
    let stage = test.temp_dir(ctx, name: f"generation-stage-${node.name}")?
    let contents = fp"${stage}/contents"
    let payload = fp"${stage}/payload.tar.gz"
    let metadata = fp"${stage}/metadata.json"
    let proof = fp"${stage}/proof.json"
    let path_value = fp"${contents}/usr/share/${node.name}"
    fs.mkdir(path_value.parent)?
    fs.write(path_value, f"payload ${node.name}\n")?
    archive.tar_create(payload, contents, [p"."], compression: "gz")?
    json.write(
      metadata,
      {
        arch: "aarch64",
        name: node.name,
        ver: node.ver,
        rel: node.rel,
        package_kind: "payload",
        files: [
          {
            path: f"usr/share/${node.name}",
            kind: "file",
            mode: 0o644,
            sha256: test_generation_sha256(f"payload ${node.name}\n"),
            target: "",
          },
        ],
      },
    )?
    fs.write(proof, f"proof ${node.name}\n")?
    let _ = store.commit(store_root, node, {payload, metadata, proof, executor_sha256})?
  }
}

proc empty_overlay(ctx: TestContext, name: Str) [fs, error] -> Result[Path] {
  let overlay = test.temp_dir(ctx, name: name)?
  fs.mkdir(fp"${overlay}/overlay")?
  fp"${overlay}/overlay"
}

proc expect_generation_error(
  ctx: TestContext,
  result: Result[types.GenerationReceipt],
  expected: Str,
) [error] {
  match result {
    Ok(_) => test.fail(f"${expected}: generation unexpectedly succeeded")?
    Err(problem) => test.contains(problem.message, expected)?
  }
}

proc test_generation_runtime_closure_excludes_build_toolchain(ctx: TestContext) [fs, env, error] {
  let build_value = generation_build_plan(ctx, "generation-runtime-plan")?
  let overlay = empty_overlay(ctx, "generation-runtime-overlay")?
  let value = generation.plan(build_value, ["app"], generation.overlay_digest(overlay)?)?
  test.eq(value.runtime_roots, ["app"])?
  test.eq([artifact.package_name for artifact in value.artifacts], ["app", "runtime-lib"])?

  let store_root = test.temp_dir(ctx, name: "generation-runtime-store")?
  stage_generation_artifacts(ctx, build_value, store_root)?
  let output = fp"${test.temp_dir(ctx, name: "generation-runtime-output")?}/root"
  let receipt = generation.compose(value, store_root, output, overlay)?
  test.eq([artifact.package_name for artifact in receipt.artifacts], ["app", "runtime-lib"])?
  test.eq(fp"${output}/usr/share/app".read_text()?, "payload app\n")?
  test.eq(fp"${output}/usr/share/runtime-lib".read_text()?, "payload runtime-lib\n")?
  test.eq(fs.exists(fp"${output}/usr/share/host-tool")?, false)?
  test.eq(fs.exists(fp"${output}/usr/share/target-sdk")?, false)?
  generation.verify_generation(output, receipt)?
}

proc test_generation_plan_and_receipt_are_deterministic_for_root_order_and_duplicates(ctx: TestContext) [fs, env, error] {
  let build_value = generation_build_plan(ctx, "generation-deterministic-plan")?
  let overlay = empty_overlay(ctx, "generation-deterministic-overlay")?
  let overlay_sha256 = generation.overlay_digest(overlay)?
  let first = generation.plan(build_value, ["runtime-lib", "app", "app"], overlay_sha256)?
  let second = generation.plan(build_value, ["app", "runtime-lib"], overlay_sha256)?
  test.eq(first, second)?
  test.eq(first.runtime_roots, ["app", "runtime-lib"])?

  let store_root = test.temp_dir(ctx, name: "generation-deterministic-store")?
  stage_generation_artifacts(ctx, build_value, store_root)?
  let first_output = fp"${test.temp_dir(ctx, name: "generation-deterministic-first")?}/root"
  let second_output = fp"${test.temp_dir(ctx, name: "generation-deterministic-second")?}/root"
  test.eq(
    generation.compose(first, store_root, first_output, overlay)?,
    generation.compose(second, store_root, second_output, overlay)?,
  )?
}

proc test_generation_rejects_missing_and_corrupt_runtime_artifacts_before_mutation(ctx: TestContext) [fs, env, error] {
  let build_value = generation_build_plan(ctx, "generation-invalid-plan")?
  let overlay = empty_overlay(ctx, "generation-invalid-overlay")?
  let value = generation.plan(build_value, ["app"], generation.overlay_digest(overlay)?)?
  let missing_store = test.temp_dir(ctx, name: "generation-missing-store")?
  let missing_output = fp"${test.temp_dir(ctx, name: "generation-missing-output")?}/root"
  expect_generation_error(ctx, generation.compose(value, missing_store, missing_output, overlay), "is missing")?
  test.eq(fs.exists(missing_output)?, false)?

  let corrupt_store = test.temp_dir(ctx, name: "generation-corrupt-store")?
  stage_generation_artifacts(ctx, build_value, corrupt_store)?
  let app = value.artifacts[0]
  fs.write(fp"${store.artifact_path(corrupt_store, app.artifact_key)}/payload.tar.gz", "corrupt payload")?
  let corrupt_output = fp"${test.temp_dir(ctx, name: "generation-corrupt-output")?}/root"
  expect_generation_error(ctx, generation.compose(value, corrupt_store, corrupt_output, overlay), "payload SHA-256 does not match receipt")?
  test.eq(fs.exists(corrupt_output)?, false)?
}

proc test_generation_profile_overlay_metadata_and_explicit_replacement(ctx: TestContext) [fs, env, error] {
  let build_value = generation_build_plan(ctx, "generation-overlay-plan")?
  let store_root = test.temp_dir(ctx, name: "generation-overlay-store")?
  stage_generation_artifacts(ctx, build_value, store_root)?
  let overlay = empty_overlay(ctx, "generation-overlay-root")?
  fs.mkdir(fp"${overlay}/etc")?
  fs.write(fp"${overlay}/etc/profile", "profile configuration\n")?
  json.write(
    fp"${overlay}/overlay.json",
    {format: "laputa-generation-overlay-1", profile: "qemu-dwl-foot", replacements: []},
  )?
  let profile = generation.overlay_profile(overlay)?
  let value = generation.plan_profile(build_value, ["app"], profile)?
  let output = fp"${test.temp_dir(ctx, name: "generation-overlay-output")?}/root"
  let receipt = generation.compose(value, store_root, output, overlay)?
  test.eq(receipt.profile.name, "qemu-dwl-foot")?
  test.eq(fp"${output}/etc/profile".read_text()?, "profile configuration\n")?
  test.eq(fs.exists(fp"${output}/overlay.json")?, false)?

  let conflict_overlay = empty_overlay(ctx, "generation-conflict-overlay")?
  fs.mkdir(fp"${conflict_overlay}/usr/share")?
  fs.write(fp"${conflict_overlay}/usr/share/app", "replaced app\n")?
  let conflict = generation.plan(build_value, ["app"], generation.overlay_digest(conflict_overlay)?)?
  let conflict_output = fp"${test.temp_dir(ctx, name: "generation-conflict-output")?}/root"
  expect_generation_error(ctx, generation.compose(conflict, store_root, conflict_output, conflict_overlay), "conflicts with package app")?
  test.eq(fs.exists(conflict_output)?, false)?

  json.write(
    fp"${conflict_overlay}/overlay.json",
    {
      format: "laputa-generation-overlay-1",
      profile: "qemu-dwl-foot",
      replacements: ["usr/share/app"],
    },
  )?
  let replacement_profile = generation.overlay_profile(conflict_overlay)?
  let replacement = generation.plan_profile(build_value, ["app"], replacement_profile)?
  let replacement_output = fp"${test.temp_dir(ctx, name: "generation-replacement-output")?}/root"
  let _ = generation.compose(replacement, store_root, replacement_output, conflict_overlay)?
  test.eq(fp"${replacement_output}/usr/share/app".read_text()?, "replaced app\n")?
}
