##! Behavior coverage for preflighted immutable roots composed from artifact-store receipts.
use pm.root
use pm.store
use pm.types

type EntrySpec = {path: Str, kind: types.FileKind, content: Str, mode: Int, target: Str}
type PreparedArtifact = {node: types.PlanNode, staged: types.StagedArtifact}

pure digest(value: Str) -> Str {
  bytes.from_text(value).sha256().hex()
}

pure payload_file(rel: Str, content: Str, mode: Int = 0o644) -> EntrySpec {
  {path: rel, kind: types.File, content, mode, target: ""}
}

pure payload_tree(rel: Str, mode: Int = 0o755) -> EntrySpec {
  {path: rel, kind: types.Tree, content: "", mode, target: ""}
}

pure payload_symlink(rel: Str, target: Str) -> EntrySpec {
  {path: rel, kind: types.Symlink, content: "", mode: 0o777, target}
}

pure metadata_rows(entries: List[EntrySpec]) -> List[Record] {
  [
    {
      path: entry.path,
      kind: types.file_kind_text(entry.kind),
      mode: entry.mode,
      sha256: if entry.kind == types.File or entry.kind == types.Binary { digest(entry.content) } else { "" },
      target: entry.target,
    }
    for entry in entries
  ]
}

proc write_payload_entry(root: Path, entry: EntrySpec) [fs, error] {
  let output = fp"${root}/${entry.path}"
  fs.mkdir(output.parent)?

  if entry.kind == types.File or entry.kind == types.Binary {
    fs.write(output, entry.content)?
    fs.chmod(output, entry.mode)?
  } else if entry.kind == types.Tree {
    fs.mkdir(output)?
    fs.chmod(output, entry.mode)?
  } else if entry.kind == types.Symlink {
    fs.symlink(fp"${entry.target}", output)?
  }
}

proc stage_artifact(
  ctx: TestContext,
  name: Str,
  kind: types.PackageKind,
  entries: List[EntrySpec],
  dependencies: List[types.PlanDependency] = [],
) [fs, error] -> Result[PreparedArtifact] {
  let stage = test.temp_dir(ctx, name: f"root-stage-${name}")?
  let contents = fp"${stage}/contents"
  let payload = fp"${stage}/payload.tar.gz"
  let metadata = fp"${stage}/metadata.json"
  let proof = fp"${stage}/proof.json"
  fs.mkdir(contents)?

  for entry in entries {
    write_payload_entry(contents, entry)?
  }

  if kind == types.Meta {
    fs.write(payload, "metapackages have no root payload")?
  } else {
    archive.tar_create(payload, contents, [p"."], compression: "gz")?
  }

  fs.write(
    metadata,
    json.encode({
      name,
      ver: "1.0.0",
      rel: "1",
      package_kind: types.package_kind_text(kind),
      files: metadata_rows(entries),
    })? + "\n",
  )?
  fs.write(proof, f"proof ${name}\n")?
  let key = digest(f"artifact ${name} ${dependencies.len()}")
  {
    node: {
      name,
      ver: "1.0.0",
      rel: "1",
      package_id: f"${name}-1.0.0-1",
      recipe_dir: p"repo/test",
      recipe_sha256: digest(f"recipe ${name}"),
      proof_sha256: digest(f"proof input ${name}"),
      artifact_key: key,
      proof_key: digest(f"proof key ${name}"),
      action: types.Build("root test"),
      level: 0,
      dependencies,
      remote: null,
    },
    staged: {payload, metadata, proof, executor_sha256: digest("root executor")},
  }
}

proc commit_artifact(
  ctx: TestContext,
  store_root: Path,
  name: Str,
  kind: types.PackageKind,
  entries: List[EntrySpec],
  dependencies: List[types.PlanDependency] = [],
) [fs, error] -> Result[types.ArtifactReceipt] {
  let prepared = stage_artifact(ctx, name, kind, entries, dependencies)?
  store.commit(store_root, prepared.node, prepared.staged)?
}

proc expect_root_error(ctx: TestContext, result: Result[types.RootPlan], expected: Str) [error] {
  match result {
    Ok(_) => test.fail(f"${expected}: root preflight unexpectedly succeeded")?
    Err(problem) => test.contains(problem.message, expected)?
  }
}

proc test_root_composes_empty_and_metapackage_roots(ctx: TestContext) [fs, error] {
  let empty = root.preflight([])?
  test.eq(empty.artifacts, [])?
  let empty_output = fp"${test.temp_dir(ctx, name: "root-empty-output")?}/root"
  let empty_receipt = root.compose(empty_output, empty, [])?
  test.eq(empty_receipt.entries, [])?
  root.verify(empty_output, empty_receipt)?

  let store_root = test.temp_dir(ctx, name: "root-meta-store")?
  let meta = commit_artifact(ctx, store_root, "meta", types.Meta, [])?
  let meta_plan = root.preflight([meta])?
  test.eq(meta_plan.artifacts[0].payload, false)?
  test.eq(meta_plan.entries, [])?
  let output = fp"${test.temp_dir(ctx, name: "root-meta-output")?}/root"
  test.eq(root.compose(output, meta_plan, [meta])?.artifacts[0].package_name, "meta")?
}

proc test_root_preserves_file_mode_symlink_and_empty_directory(ctx: TestContext) [fs, error] {
  let store_root = test.temp_dir(ctx, name: "root-single-store")?
  let receipt = commit_artifact(
    ctx,
    store_root,
    "single",
    types.Payload,
    [
      payload_file("usr/bin/tool", "tool", mode: 0o755),
      payload_tree("usr/share/empty"),
      payload_symlink("bin/tool", "../usr/bin/tool"),
    ],
  )?
  let plan = root.preflight([receipt])?
  let output = fp"${test.temp_dir(ctx, name: "root-single-output")?}/root"
  let composed = root.compose(output, plan, [receipt])?
  test.eq(fs.metadata(fp"${output}/usr/bin/tool")?.mode % 512, 0o755)?
  test.eq(fp"${output}/bin/tool".readlink()?.display(), "../usr/bin/tool")?
  test.eq(fs.metadata(fp"${output}/usr/share/empty")?.kind, "dir")?
  root.verify(output, composed)?
}

proc test_root_plan_and_receipt_are_deterministic_for_multiple_artifacts(ctx: TestContext) [fs, error] {
  let store_root = test.temp_dir(ctx, name: "root-multiple-store")?
  let alpha = commit_artifact(ctx, store_root, "alpha", types.Payload, [payload_file("usr/share/alpha", "a")])?
  let beta = commit_artifact(ctx, store_root, "beta", types.Payload, [payload_file("usr/share/beta", "b")])?
  let first = root.preflight([beta, alpha])?
  let second = root.preflight([alpha, beta])?
  test.eq(first, second)?
  test.eq([artifact.package_name for artifact in first.artifacts], ["alpha", "beta"])?
  let first_output = fp"${test.temp_dir(ctx, name: "root-multiple-first")?}/root"
  let second_output = fp"${test.temp_dir(ctx, name: "root-multiple-second")?}/root"
  test.eq(root.compose(first_output, first, [alpha, beta])?, root.compose(second_output, second, [beta, alpha])?)?
}

proc test_root_rejects_collisions_and_same_owner_duplicate_entries_before_mutation(ctx: TestContext) [fs, error] {
  let store_root = test.temp_dir(ctx, name: "root-collision-store")?
  let left = commit_artifact(ctx, store_root, "left", types.Payload, [payload_file("usr/bin/shared", "left")])?
  let right = commit_artifact(ctx, store_root, "right", types.Payload, [payload_file("usr/bin/shared", "right")])?
  expect_root_error(ctx, root.preflight([left, right]), "owned by both")?
  let collision_output = fp"${test.temp_dir(ctx, name: "root-collision-output")?}/root"
  let empty_plan = root.preflight([])?

  match root.compose(collision_output, empty_plan, [left, right]) {
    Ok(_) => test.fail("colliding artifacts unexpectedly composed")?
    Err(problem) => test.contains(problem.message, "owned by both")?
  }

  test.eq(fs.exists(collision_output)?, false)?

  let duplicate = stage_artifact(ctx, "duplicate", types.Payload, [payload_file("usr/bin/duplicate", "one")])?
  fs.write(
    duplicate.staged.metadata,
    json.encode({
      name: "duplicate",
      ver: "1.0.0",
      rel: "1",
      package_kind: "payload",
      files: metadata_rows([payload_file("usr/bin/duplicate", "one"), payload_file("usr/bin/duplicate", "one")]),
    })? + "\n",
  )?
  let same_owner = store.commit(store_root, duplicate.node, duplicate.staged)?
  expect_root_error(ctx, root.preflight([same_owner]), "repeats usr/bin/duplicate")?
}

proc test_root_rejects_traversal_and_corrupt_payloads(ctx: TestContext) [fs, error] {
  let store_root = test.temp_dir(ctx, name: "root-invalid-store")?
  let traversal = stage_artifact(ctx, "traversal", types.Payload, [payload_file("usr/bin/safe", "safe")])?
  fs.write(
    traversal.staged.metadata,
    json.encode({
      name: "traversal",
      ver: "1.0.0",
      rel: "1",
      package_kind: "payload",
      files: [{path: "../escape", kind: "file", mode: 0o644, sha256: digest("safe"), target: ""}],
    })? + "\n",
  )?
  let traversal_receipt = store.commit(store_root, traversal.node, traversal.staged)?
  expect_root_error(ctx, root.preflight([traversal_receipt]), "must stay relative")?

  let invalid_link = stage_artifact(ctx, "invalid-link", types.Payload, [payload_file("usr/bin/unused", "unused")])?
  fs.write(
    invalid_link.staged.metadata,
    json.encode({
      name: "invalid-link",
      ver: "1.0.0",
      rel: "1",
      package_kind: "payload",
      files: [{path: "bin/invalid", kind: "symlink", mode: 0o777, sha256: "", target: "../../outside"}],
    })? + "\n",
  )?
  let invalid_link_receipt = store.commit(store_root, invalid_link.node, invalid_link.staged)?
  expect_root_error(ctx, root.preflight([invalid_link_receipt]), "escapes the root")?

  let receipt = commit_artifact(ctx, store_root, "corrupt", types.Payload, [payload_file("usr/bin/corrupt", "clean")])?
  fs.write(fp"${receipt.artifact_dir}/payload.tar.gz", "corrupt payload")?
  expect_root_error(ctx, root.preflight([receipt]), "payload SHA-256 does not match receipt")?
}

proc test_root_runtime_closure_ignores_build_only_dependency(ctx: TestContext) [fs, error] {
  let store_root = test.temp_dir(ctx, name: "root-runtime-store")?
  let runtime = commit_artifact(ctx, store_root, "runtime", types.Payload, [payload_file("usr/lib/runtime", "runtime")])?
  let toolchain = commit_artifact(ctx, store_root, "toolchain", types.Payload, [payload_file("usr/bin/compiler", "compiler")])?
  let app = commit_artifact(
    ctx,
    store_root,
    "app",
    types.Payload,
    [payload_file("usr/bin/app", "app")],
    [
      {name: "runtime", kind: types.Runtime, artifact_key: runtime.key},
      {name: "toolchain", kind: types.BuildHost, artifact_key: toolchain.key},
    ],
  )?
  test.eq(app.runtime_dependency_keys, [runtime.key])?
  expect_root_error(ctx, root.preflight([app]), "runtime dependency artifact")?
  let plan = root.preflight([app, runtime])?
  let output = fp"${test.temp_dir(ctx, name: "root-runtime-output")?}/root"
  let _ = root.compose(output, plan, [app, runtime])?
  test.ok(fs.exists(fp"${output}/usr/bin/app")?)?
  test.ok(fs.exists(fp"${output}/usr/lib/runtime")?)?
  test.eq(fs.exists(fp"${output}/usr/bin/compiler")?, false)?
}

proc test_root_failed_composition_leaves_completed_output_untouched(ctx: TestContext) [fs, error] {
  let store_root = test.temp_dir(ctx, name: "root-immutable-store")?
  let artifact = commit_artifact(ctx, store_root, "immutable", types.Payload, [payload_file("usr/bin/immutable", "new")])?
  let plan = root.preflight([artifact])?
  let output = fp"${test.temp_dir(ctx, name: "root-immutable-output")?}/root"
  fs.mkdir(output)?
  fs.write(fp"${output}/marker", "previous root")?

  match root.compose(output, plan, [artifact]) {
    Ok(_) => test.fail("completed root was overwritten")?
    Err(problem) => test.contains(problem.message, "already exists")?
  }

  test.eq(fp"${output}/marker".read_text()?, "previous root")?
}
