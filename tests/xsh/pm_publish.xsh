##! Behavior coverage for verified BuildPlan repository snapshots and immutable file publication.
use pm.catalog
use pm.plan
use pm.policy
use pm.proof as pm_proof
use pm.remote
use pm.repo
use pm.store
use pm.types

type PublishedMetadataDto = {
  target: Str,
  artifact_key: Str,
  recipe_sha256: Str,
  executor_sha256: Str,
  proof_key: Str,
  proof_sha256: Str,
}

pure fixture(name: Str) -> Path {
  fp"tests/xsh/fixtures/${name}"
}

pure publish_executor_identity() -> types.ExecutorIdentity {
  {
    format: "laputa-pm-executor-1",
    pm_sha256: "pm-tree",
    xsh_sha256: "xsh-runners",
    core_sha256: "core-tree",
  }
}

pure publish_empty_remote() -> types.RemoteSnapshot {
  {target: types.Aarch64LinuxMusl, index_sha256: "publish-empty-remote", packages: []}
}

proc copied_publish_repository(ctx: TestContext, name: Str) [fs, env, error] -> Result[Path] {
  let root = test.temp_dir(ctx, name: name)?
  let _ = fs.copy_tree(fixture("graph-catalog/repo"), fp"${root}/repo", parents: true, overwrite: true)?
  fs.mkdir(fp"${root}/pm")?
  fs.copy(p"pm/proof.xsh", fp"${root}/pm/proof.xsh", overwrite: true)?
  root
}

proc publish_plan(ctx: TestContext, name: Str) [fs, env, error] -> Result[types.BuildPlan] {
  let repo_root = copied_publish_repository(ctx, name)?
  let catalog_value = catalog.load(repo_root)?
  plan.resolve(catalog_value, publish_empty_remote(), policy.aarch64_docker(), ["app"], false, publish_executor_identity())?
}

proc node_named(value: types.BuildPlan, name: Str) [error] -> Result[types.PlanNode] {
  for node in value.nodes {
    if node.name == name {
      return node
    }
  }

  return Err(types.PmError.PackageContract(f"missing published node ${name}"))
}

proc stage_plan_artifacts(
  ctx: TestContext,
  value: types.BuildPlan,
  store_root: Path,
  valid_proofs: Bool = true,
) [fs, error] {
  let executor_sha256 = plan.executor_fingerprint(value.executor)?

  for node in value.nodes {
    let staged_root = test.temp_dir(ctx, name: f"publish-stage-${node.name}")?
    let payload = fp"${staged_root}/payload.tar.gz"
    let metadata = fp"${staged_root}/metadata.json"
    let proof = fp"${staged_root}/proof.json"
    fs.write(payload, f"payload ${node.package_id}\n")?
    json.write(
      metadata,
      {
        arch: "aarch64",
        name: node.name,
        ver: node.ver,
        rel: node.rel,
        package_kind: "payload",
        files: [],
      },
    )?

    if valid_proofs {
      pm_proof.write_artifact_receipt(proof, node, payload)?
    } else {
      fs.write(proof, "not a package proof receipt\n")?
    }

    let _ = store.commit(store_root, node, {payload, metadata, proof, executor_sha256})?
  }
}

proc expect_snapshot_error(ctx: TestContext, value: types.BuildPlan, store_root: Path, expected: Str) [fs, error] {
  match repo.snapshot(value, store_root) {
    Ok(_) => test.fail(f"${expected}: snapshot unexpectedly succeeded")?
    Err(problem) => test.contains(problem.message, expected)?
  }
}

proc test_snapshot_rejects_missing_unproved_and_corrupt_plan_artifacts(ctx: TestContext) [fs, env, error] {
  let value = publish_plan(ctx, "publish-missing-repo")?
  let missing_store = test.temp_dir(ctx, name: "publish-missing-store")?
  expect_snapshot_error(ctx, value, missing_store, "is missing")?

  let unproved_store = test.temp_dir(ctx, name: "publish-unproved-store")?
  stage_plan_artifacts(ctx, value, unproved_store, valid_proofs: false)?
  expect_snapshot_error(ctx, value, unproved_store, "invalid JSON")?

  let incomplete_store = test.temp_dir(ctx, name: "publish-incomplete-store")?
  stage_plan_artifacts(ctx, value, incomplete_store)?
  let incomplete_app = node_named(value, "app")?
  fs.remove(fp"${store.artifact_path(incomplete_store, incomplete_app.artifact_key)}/metadata.json")?
  expect_snapshot_error(ctx, value, incomplete_store, "incomplete")?

  let corrupt_store = test.temp_dir(ctx, name: "publish-corrupt-store")?
  stage_plan_artifacts(ctx, value, corrupt_store)?
  let app = node_named(value, "app")?
  fs.write(fp"${store.artifact_path(corrupt_store, app.artifact_key)}/payload.tar.gz", "corrupt payload")?
  expect_snapshot_error(ctx, value, corrupt_store, "payload SHA-256 does not match receipt")?
}

proc test_publish_file_snapshot_is_exact_deterministic_and_idempotent(ctx: TestContext) [fs, net, env, time, error] {
  let value = publish_plan(ctx, "publish-file-repo")?
  let store_root = test.temp_dir(ctx, name: "publish-file-store")?
  stage_plan_artifacts(ctx, value, store_root)?
  let snapshot = repo.snapshot(value, store_root)?
  let remote_root = test.temp_dir(ctx, name: "publish-file-remote")?
  let work = test.temp_dir(ctx, name: "publish-file-work")?
  let remote_url = f"file://${remote_root}"
  repo.publish(snapshot, remote_url, "", work)?

  let index = remote.load_remote_index_from(fp"${remote_root}/index.json")?
  test.eq([entry.name for entry in index], ["app", "host-tool", "runtime-lib", "target-sdk"])?
  let app = node_named(value, "app")?
  let entry = index[0]
  test.eq(entry.artifact_key, app.artifact_key)?
  test.eq(entry.proof_key, app.proof_key)?
  test.eq(entry.proof_sha256, app.proof_sha256)?
  test.ok(entry.metadata_sha256 != "")?
  test.ok(fp"${remote_root}/${entry.tarball}".exists()?)?
  test.ok(fp"${remote_root}/${entry.metadata}".exists()?)?
  test.ok(fp"${remote_root}/${entry.proof}".exists()?)?
  let metadata = json.read(fp"${remote_root}/${entry.metadata}")?.require(PublishedMetadataDto)?
  test.eq(metadata.target, "aarch64-linux-musl")?
  test.eq(metadata.artifact_key, app.artifact_key)?
  test.eq(metadata.recipe_sha256, app.recipe_sha256)?
  test.eq(metadata.executor_sha256, plan.executor_fingerprint(value.executor)?)?
  test.eq(metadata.proof_key, app.proof_key)?
  test.eq(metadata.proof_sha256, app.proof_sha256)?

  let first_index = fs.read_text(fp"${remote_root}/index.json")?
  repo.publish(snapshot, remote_url, "", work)?
  test.eq(fs.read_text(fp"${remote_root}/index.json")?, first_index)?
}

proc test_publish_conflict_and_failed_object_do_not_switch_file_index(ctx: TestContext) [fs, net, env, time, error] {
  let value = publish_plan(ctx, "publish-conflict-repo")?
  let store_root = test.temp_dir(ctx, name: "publish-conflict-store")?
  stage_plan_artifacts(ctx, value, store_root)?
  let snapshot = repo.snapshot(value, store_root)?
  let remote_root = test.temp_dir(ctx, name: "publish-conflict-remote")?
  let work = test.temp_dir(ctx, name: "publish-conflict-work")?
  let remote_url = f"file://${remote_root}"
  let app = node_named(value, "app")?
  let blocked_metadata = fp"${remote_root}/metadata/aarch64/${app.name}/${app.package_id}.json"
  fs.mkdir(blocked_metadata.parent)?
  fs.write(blocked_metadata, "different immutable metadata")?
  json.write(fp"${remote_root}/index.json", [])?

  match repo.publish(snapshot, remote_url, "", work) {
    Ok(_) => test.fail("conflicting immutable metadata unexpectedly published")?
    Err(problem) => test.contains(problem.message, "already exists with different bytes")?
  }

  let unchanged_index = fs.read_text(fp"${remote_root}/index.json")?
  test.eq(unchanged_index, "[]")?
  test.ok(fp"${remote_root}/packages/aarch64/${app.name}/${app.package_id}.tar.gz".exists()?)?

  let clean_remote = test.temp_dir(ctx, name: "publish-tuple-conflict-remote")?
  let clean_work = test.temp_dir(ctx, name: "publish-tuple-conflict-work")?
  let clean_url = f"file://${clean_remote}"
  repo.publish(snapshot, clean_url, "", clean_work)?
  let raw = remote.load_remote_index_from(fp"${clean_remote}/index.json")?
  fs.write(fp"${clean_remote}/index.json", json.encode([{...raw[0], sha256: "different tuple bytes"}])? + "\n")?

  match repo.publish(snapshot, clean_url, "", clean_work) {
    Ok(_) => test.fail("conflicting immutable tuple unexpectedly published")?
    Err(problem) => test.contains(problem.message, "already exists with different content")?
  }
}

proc test_remote_decoder_preserves_legacy_fallback_and_new_identity(ctx: TestContext) [fs, net, env, error] {
  let legacy = remote.decode_remote_package({
    arch: "aarch64",
    name: "legacy",
    ver: "1",
    rel: "1",
    deps: [],
    mkdeps: [],
    sha256: "payload",
    size: 1,
    tarball: "packages/aarch64/legacy/legacy-1-1.tar.gz",
    metadata: "metadata/aarch64/legacy/legacy-1-1.json",
    source_sha256: "",
    metapackage: false,
  })?
  let legacy_plan = remote.plan_artifact_from_package(legacy)?
  test.eq(legacy.artifact_key, "")?
  test.eq(legacy_plan.artifact_key, "")?
  test.ok(legacy_plan.retrieval.metadata_sha256 != "")?

  let modern = remote.decode_remote_package({
    arch: "aarch64",
    name: "modern",
    ver: "1",
    rel: "1",
    deps: [],
    mkdeps_host: [],
    mkdeps_target: [],
    sha256: "payload",
    size: 1,
    tarball: "packages/aarch64/modern/modern-1-1.tar.gz",
    metadata: "metadata/aarch64/modern/modern-1-1.json",
    metadata_sha256: "metadata",
    artifact_key: "artifact",
    recipe_sha256: "recipe",
    executor_sha256: "executor",
    proof_key: "proof-key",
    proof_sha256: "proof-input",
    proof: "proofs/aarch64/modern/modern-1-1.json",
    proof_receipt_sha256: "proof-receipt",
    source_sha256: "",
    metapackage: false,
  })?
  let modern_plan = remote.plan_artifact_from_package(modern)?
  test.eq(modern_plan.artifact_key, "artifact")?
  test.eq(modern_plan.retrieval.metadata_sha256, "metadata")?

  let value = publish_plan(ctx, "publish-legacy-import-repo")?
  let node = node_named(value, "app")?
  let remote_root = test.temp_dir(ctx, name: "publish-legacy-import-remote")?
  let payload = fp"${remote_root}/packages/aarch64/app/app-1-1.tar.gz"
  let metadata = fp"${remote_root}/metadata/aarch64/app/app-1-1.json"
  fs.mkdir(payload.parent)?
  fs.mkdir(metadata.parent)?
  fs.write(payload, "legacy remote payload")?
  json.write(metadata, {name: node.name, ver: node.ver, rel: node.rel, executor_sha256: plan.executor_fingerprint(value.executor)?})?
  let imported_store = test.temp_dir(ctx, name: "publish-legacy-import-store")?
  let imported = store.import_remote(
    imported_store,
    {
      ...node,
      action: types.ReuseRemote("legacy remote artifact"),
      remote: {
        arch: "aarch64",
        tarball: payload.relative_to(remote_root).display(),
        tarball_sha256: hash.sha256(payload)?.hex(),
        metadata: metadata.relative_to(remote_root).display(),
        metadata_sha256: hash.sha256(metadata)?.hex(),
      },
    },
    f"file://${remote_root}",
    test.temp_dir(ctx, name: "publish-legacy-import-cache")?,
  )?
  test.eq(imported.origin, types.Remote)?
}

proc test_publish_requires_token_only_for_network_remote(ctx: TestContext) [fs, net, env, time, error] {
  let value = publish_plan(ctx, "publish-token-repo")?
  let store_root = test.temp_dir(ctx, name: "publish-token-store")?
  stage_plan_artifacts(ctx, value, store_root)?
  let snapshot = repo.snapshot(value, store_root)?
  let work = test.temp_dir(ctx, name: "publish-token-work")?

  match repo.publish(snapshot, "https://example.invalid/repo", "", work) {
    Ok(_) => test.fail("network publication without a token unexpectedly succeeded")?
    Err(problem) => test.contains(problem.message, "needs a token")?
  }
}
