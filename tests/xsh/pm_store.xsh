##! Behavior coverage for immutable package artifact-store publication and verification.
use pm.store
use pm.types

type TestStage = {root: Path, staged: types.StagedArtifact}
type ReceiptDto = {
  format: Str,
  key: Str,
  target: Str,
  package_name: Str,
  package_id: Str,
  origin: Str,
  recipe_sha256: Str,
  executor_sha256: Str,
  payload_sha256: Str,
  metadata_sha256: Str,
  proof_key: Str,
  proof_sha256: Str,
  dependency_keys: List[Str],
  runtime_dependency_keys: List[Str],
}

pure digest(value: Str) -> Str {
  bytes.from_text(value).sha256().hex()
}

pure test_node(key: Str) -> types.PlanNode {
  {
    name: "demo",
    ver: "1.0.0",
    rel: "1",
    package_id: "demo-1.0.0-1",
    recipe_dir: p"repo/demo",
    recipe_sha256: digest("recipe"),
    proof_sha256: digest("proof-input"),
    artifact_key: key,
    proof_key: digest("proof-key"),
    action: types.Build("test build"),
    level: 0,
    dependencies: [],
    remote: null,
  }
}

proc staged_artifact(ctx: TestContext, name: Str, payload: Str = "payload", metadata: Str = "metadata", proof: Str = "proof") [fs, error] -> Result[TestStage] {
  let root = test.temp_dir(ctx, name: name)?
  let payload_path = fp"${root}/payload.tar.gz"
  let metadata_path = fp"${root}/metadata.json"
  let proof_path = fp"${root}/proof.json"
  fs.write(payload_path, payload)?
  fs.write(metadata_path, metadata)?
  fs.write(proof_path, proof)?
  {
    root,
    staged: {
      payload: payload_path,
      metadata: metadata_path,
      proof: proof_path,
      executor_sha256: digest("executor"),
    },
  }
}

proc store_root(ctx: TestContext, name: Str) [fs, error] -> Result[Path] {
  test.temp_dir(ctx, name: name)
}

proc expect_store_error(ctx: TestContext, result: Result[types.ArtifactReceipt], expected: Str) [error] {
  match result {
    Ok(_) => test.fail(f"${expected}: operation unexpectedly succeeded")?
    Err(problem) => test.contains(problem.message, expected)?
  }
}

proc test_store_rejects_missing_and_invalid_keys(ctx: TestContext) [fs, error] {
  let root = store_root(ctx, "store-missing")?
  let key = digest("missing")
  expect_store_error(ctx, store.lookup(root, key), "is missing")?
  expect_store_error(ctx, store.lookup(root, "../not-a-key"), "artifact key must be a lowercase SHA-256 digest")?
}

proc test_store_commits_atomically_and_reuses_exact_artifact(ctx: TestContext) [fs, error] {
  let root = store_root(ctx, "store-commit")?
  let key = digest("commit")
  let first_stage = staged_artifact(ctx, "store-commit-first", payload: "first payload")?
  let first = store.commit(root, test_node(key), first_stage.staged)?
  let final_dir = store.artifact_path(root, key)
  test.eq(first.origin, types.Built)?
  test.eq(first.key, key)?
  test.ok(fs.exists(fp"${final_dir}/artifact.json")?)?
  test.eq(store.lookup(root, key)?, first)?

  let replacement = staged_artifact(ctx, "store-commit-replacement", payload: "replacement payload")?
  let reused = store.commit(root, test_node(key), replacement.staged)?
  test.eq(reused, first)?
  test.eq(fp"${final_dir}/payload.tar.gz".read_text()?, "first payload")?
}

proc test_store_discards_incomplete_temporary_artifacts(ctx: TestContext) [fs, error] {
  let root = store_root(ctx, "store-temporary")?
  let key = digest("temporary")
  let temporary = fp"${root}/v1/tmp/${key}"
  fs.mkdir(temporary)?
  fs.write(fp"${temporary}/payload.tar.gz", "incomplete")?
  let receipt = store.commit(root, test_node(key), staged_artifact(ctx, "store-temporary-stage")?.staged)?
  test.eq(receipt.key, key)?
  test.eq(fs.exists(temporary)?, false)?
}

proc test_store_serializes_duplicate_concurrent_commits(ctx: TestContext) [fs, process, env, error] {
  let root = store_root(ctx, "store-concurrent")?
  let key = digest("concurrent")
  let stage = staged_artifact(ctx, "store-concurrent-stage")?
  let script = fp"${test.temp_dir(ctx, name: "store-concurrent-script")?}/commit.xsh"
  fs.write(
    script,
    r"""use pm.store
use pm.types

pure digest(value: Str) -> Str {
  bytes.from_text(value).sha256().hex()
}

proc main(...argv: List[Str]) [fs, error] {
  let node: types.PlanNode = {
    name: "demo",
    ver: "1.0.0",
    rel: "1",
    package_id: "demo-1.0.0-1",
    recipe_dir: p"repo/demo",
    recipe_sha256: digest("recipe"),
    proof_sha256: digest("proof-input"),
    artifact_key: argv[1],
    proof_key: digest("proof-key"),
    action: types.Build("concurrent test build"),
    level: 0,
    dependencies: [],
    remote: null,
  }
  let _ = store.commit(
    fp"${argv[0]}",
    node,
    {payload: fp"${argv[2]}", metadata: fp"${argv[3]}", proof: fp"${argv[4]}", executor_sha256: digest("executor")},
  )?
}

main(@args)?
""",
  )?
  let configured = env.get("XSH_HOST") ?? ""
  let runner = if configured != "" { fp"${configured}" } else { process.which("xsh")? }
  let first = spawn run $runner $script $root $key ${stage.staged.payload} ${stage.staged.metadata} ${stage.staged.proof} ?
  let second = spawn run $runner $script $root $key ${stage.staged.payload} ${stage.staged.metadata} ${stage.staged.proof} ?
  let statuses = wait [first, second]?
  test.ok(statuses[0].ok)?
  test.ok(statuses[1].ok)?
  test.eq(store.lookup(root, key)?.key, key)?
}

proc test_store_detects_payload_receipt_and_key_corruption(ctx: TestContext) [fs, error] {
  let root = store_root(ctx, "store-corrupt")?
  let key = digest("corrupt")
  let final_dir = store.artifact_path(root, key)
  let stage = staged_artifact(ctx, "store-corrupt-stage")?
  let _ = store.commit(root, test_node(key), stage.staged)?

  fs.write(fp"${final_dir}/payload.tar.gz", "corrupted payload")?
  expect_store_error(ctx, store.verify_artifact(root, key), "payload SHA-256 does not match receipt")?

  fs.write(fp"${final_dir}/payload.tar.gz", "payload")?
  fs.write(fp"${final_dir}/artifact.json", "not JSON")?
  expect_store_error(ctx, store.verify_artifact(root, key), "invalid JSON")?

  let clean_root = store_root(ctx, "store-key-corrupt")?
  let clean_dir = store.artifact_path(clean_root, key)
  let _ = store.commit(clean_root, test_node(key), staged_artifact(ctx, "store-key-corrupt-stage")?.staged)?
  let raw = json.read(fp"${clean_dir}/artifact.json")?.require(ReceiptDto)?
  fs.write(fp"${clean_dir}/artifact.json", json.encode({...raw, key: digest("other key")})? + "\n")?
  expect_store_error(ctx, store.verify_artifact(clean_root, key), "does not match")?
}

proc test_store_staging_failure_never_publishes_final(ctx: TestContext) [fs, error] {
  let root = store_root(ctx, "store-staging-failure")?
  let key = digest("staging-failure")
  let stage = staged_artifact(ctx, "store-staging-failure-stage")?
  let broken = {...stage.staged, payload: fp"${stage.root}/missing-payload.tar.gz"}
  expect_store_error(ctx, store.commit(root, test_node(key), broken), "No such file")?
  test.eq(fs.exists(store.artifact_path(root, key))?, false)?
}

pure remote_node(key: Str, payload: Str, metadata: Str) -> types.PlanNode {
  {
    ...test_node(key),
    action: types.ReuseRemote("exact remote artifact"),
    remote: {
      arch: "aarch64",
      tarball: "packages/aarch64/demo/demo-1.0.0-1.tar.gz",
      tarball_sha256: digest(payload),
      metadata: "metadata/aarch64/demo/demo-1.0.0-1.json",
      metadata_sha256: digest(metadata),
    },
  }
}

proc remote_fixture(ctx: TestContext, name: Str, payload: Str, metadata: Str) [fs, error] -> Result[Path] {
  let root = test.temp_dir(ctx, name: name)?
  let tarball = fp"${root}/packages/aarch64/demo/demo-1.0.0-1.tar.gz"
  let metadata_path = fp"${root}/metadata/aarch64/demo/demo-1.0.0-1.json"
  fs.mkdir(tarball.parent)?
  fs.mkdir(metadata_path.parent)?
  fs.write(tarball, payload)?
  fs.write(metadata_path, metadata)?
  root
}

proc test_store_imports_verified_remote_artifact(ctx: TestContext) [fs, net, error] {
  let payload = "remote payload"
  let metadata = json.encode({name: "demo", ver: "1.0.0", rel: "1", executor_sha256: digest("remote executor")})?
  let remote_root = remote_fixture(ctx, "store-remote", payload, metadata)?
  let root = store_root(ctx, "store-remote-local")?
  let key = digest("remote")
  let receipt = store.import_remote(root, remote_node(key, payload, metadata), f"file://${remote_root}", test.temp_dir(ctx, name: "store-remote-cache")?)?
  test.eq(receipt.origin, types.Remote)?
  test.eq(receipt.payload_sha256, digest(payload))?
  test.eq(store.verify_artifact(root, key)?, receipt)?
}

proc test_store_rejects_remote_hash_and_metadata_mismatches(ctx: TestContext) [fs, net, error] {
  let payload = "actual remote payload"
  let metadata = json.encode({name: "demo", ver: "1.0.0", rel: "1", executor_sha256: digest("remote executor")})?
  let remote_root = remote_fixture(ctx, "store-remote-mismatch", payload, metadata)?
  let repo = f"file://${remote_root}"
  let root = store_root(ctx, "store-remote-hash-local")?
  let key = digest("remote-hash-mismatch")
  let bad_hash_node = remote_node(key, "different expected payload", metadata)
  expect_store_error(ctx, store.import_remote(root, bad_hash_node, repo, test.temp_dir(ctx, name: "store-remote-hash-cache")?), "payload SHA-256 mismatch")?
  test.eq(fs.exists(store.artifact_path(root, key))?, false)?

  let bad_metadata = json.encode({name: "not-demo", ver: "1.0.0", rel: "1", executor_sha256: digest("remote executor")})?
  let metadata_remote = remote_fixture(ctx, "store-remote-metadata", payload, bad_metadata)?
  let metadata_key = digest("remote-metadata-mismatch")
  expect_store_error(
    ctx,
    store.import_remote(
      root,
      remote_node(metadata_key, payload, bad_metadata),
      f"file://${metadata_remote}",
      test.temp_dir(ctx, name: "store-remote-metadata-cache")?,
    ),
    "remote metadata does not match plan node",
  )?
  test.eq(fs.exists(store.artifact_path(root, metadata_key))?, false)?
}
