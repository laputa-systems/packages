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

proc write_legacy_sidecar_metadata(
  staged: types.StagedArtifact,
  name: Str,
  entries: List[EntrySpec],
) [fs, error] {
  fs.write(
    staged.metadata,
    json.encode({
      arch: "aarch64",
      name,
      ver: "1.0.0",
      rel: "1",
      deps: [],
      mkdeps_host: [],
      mkdeps_target: [],
      filetree: [{path: entry.path, kind: types.file_kind_text(entry.kind)} for entry in entries],
      manifest: [entry.path for entry in entries],
      files: metadata_rows(entries),
    })? + "\n",
  )?
}

proc rewrite_legacy_database_payload(
  ctx: TestContext,
  staged: types.StagedArtifact,
  name: Str,
  entries: List[EntrySpec],
  unexpected: Bool = false,
) [fs, error] {
  let contents = test.temp_dir(ctx, name: f"root-legacy-payload-${name}")?

  for entry in entries {
    write_payload_entry(contents, entry)?
  }

  let database = fp"${contents}/var/lib/xsh-pm/packages/${name}"
  fs.mkdir(database, parents: true)?
  fs.write(fp"${database}/manifest.json", json.encode([entry.path for entry in entries])?)?
  let etcsums = [
    {path: entry.path, sha256: digest(entry.content)}
    for entry in entries
    if (entry.kind == types.file_kind_file() or entry.kind == types.file_kind_binary()) and entry.path.starts_with("etc/")
  ]
  fs.write(fp"${database}/etcsums.json", json.encode(etcsums)?)?
  fs.write(
    fp"${database}/metadata.json",
    json.encode({
      name,
      ver: "1.0.0",
      rel: "1",
      deps: [],
      mkdeps_host: [],
      mkdeps_target: [],
      filetree: [{path: entry.path, kind: types.file_kind_text(entry.kind)} for entry in entries],
      nostrip: false,
      dir: f"/var/tmp/pm-build/${name}-1.0.0-1/pkg",
      extract_install: true,
    })?,
  )?

  if unexpected {
    fs.write(fp"${database}/unexpected.json", "not a known legacy package database record")?
  }

  archive.tar_create(staged.payload, contents, [p"."], compression: "gz", overwrite: true)?
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
  let empty_receipt = root.compose_artifacts(empty_output, empty, [])?
  test.eq(empty_receipt.entries, [])?
  root.verify(empty_output, empty_receipt)?

  let store_root = test.temp_dir(ctx, name: "root-meta-store")?
  let meta = commit_artifact(ctx, store_root, "meta", types.Meta, [])?
  let meta_plan = root.preflight([meta])?
  test.eq(meta_plan.artifacts[0].payload, false)?
  test.eq(meta_plan.entries, [])?
  let output = fp"${test.temp_dir(ctx, name: "root-meta-output")?}/root"
  test.eq(root.compose_artifacts(output, meta_plan, [meta])?.artifacts[0].package_name, "meta")?
}

proc test_root_legacy_metadata_defaults_only_omitted_package_kind_to_payload(ctx: TestContext) [fs, error] {
  let store_root = test.temp_dir(ctx, name: "root-legacy-metadata-store")?
  let entries = [payload_file("usr/bin/legacy", "legacy", mode: 0o755)]
  let legacy = stage_artifact(ctx, "legacy", types.Payload, entries)?
  # The legacy remote boundary had the verified `files` inventory but no
  # package_kind. Root decoding owns the one payload-default compatibility rule.
  write_legacy_sidecar_metadata(legacy.staged, "legacy", entries)?
  rewrite_legacy_database_payload(ctx, legacy.staged, "legacy", entries)?
  let receipt = store.commit(store_root, legacy.node, legacy.staged)?
  let plan = root.preflight([receipt])?
  test.eq(plan.artifacts[0].payload, true)?
  test.eq(plan.entries[0].path, "usr/bin/legacy")?
  test.eq(plan.entries.len(), 4)?
  let output = fp"${test.temp_dir(ctx, name: "root-legacy-metadata-output")?}/root"
  let composed = root.compose_artifacts(output, plan, [receipt])?
  test.ok(fs.exists(fp"${output}/var/lib/xsh-pm/packages/legacy/metadata.json")?)?
  root.verify(output, composed)?

  let unexpected = stage_artifact(ctx, "legacy-extra", types.Payload, entries)?
  write_legacy_sidecar_metadata(unexpected.staged, "legacy-extra", entries)?
  rewrite_legacy_database_payload(ctx, unexpected.staged, "legacy-extra", entries, unexpected: true)?
  let unexpected_receipt = store.commit(store_root, unexpected.node, unexpected.staged)?
  expect_root_error(
    ctx,
    root.preflight([unexpected_receipt]),
    "payload contains undeclared var/lib/xsh-pm/packages/legacy-extra/unexpected.json",
  )?

  let invalid = stage_artifact(ctx, "invalid-kind", types.Payload, entries)?
  fs.write(
    invalid.staged.metadata,
    json.encode({
      name: "invalid-kind",
      ver: "1.0.0",
      rel: "1",
      package_kind: "",
      files: metadata_rows(entries),
    })? + "\n",
  )?
  let invalid_receipt = store.commit(store_root, invalid.node, invalid.staged)?
  expect_root_error(ctx, root.preflight([invalid_receipt]), "invalid package kind")?
}

proc test_root_preserves_file_mode_symlink_and_empty_directory(ctx: TestContext) [fs, error] {
  let store_root = test.temp_dir(ctx, name: "root-single-store")?
  # The receipt validates the lexically contained late link without resolving
  # its target; package composition may supply that target later.
  let receipt = commit_artifact(
    ctx,
    store_root,
    "single",
    types.Payload,
    [
      payload_file("usr/bin/tool", "tool", mode: 0o755),
      payload_tree("usr/share/empty", mode: 0o700),
      payload_symlink("bin/tool", "../usr/bin/tool"),
      payload_symlink("usr/lib/late-link", "late-target"),
    ],
  )?
  let plan = root.preflight([receipt])?
  let output = fp"${test.temp_dir(ctx, name: "root-single-output")?}/root"
  let composed = root.compose_artifacts(output, plan, [receipt])?
  test.eq(fs.metadata(fp"${output}/usr/bin/tool")?.mode % 512, 0o755)?
  test.eq(fp"${output}/bin/tool".readlink()?.display(), "../usr/bin/tool")?
  let empty_metadata = fs.metadata(fp"${output}/usr/share/empty")?
  test.eq(empty_metadata.kind, "dir")?
  test.eq(empty_metadata.mode % 512, 0o700)?
  root.verify(output, composed)?
}

proc test_root_rejects_cyclic_payload_link_that_differs_from_receipt(ctx: TestContext) [fs, error] {
  let store_root = test.temp_dir(ctx, name: "root-symlink-loop-store")?
  let prepared = stage_artifact(
    ctx,
    "loop-link",
    types.Payload,
    [payload_symlink("usr/lib/link", "expected-target")],
  )?
  let payload_root = test.temp_dir(ctx, name: "root-symlink-loop-payload")?
  fs.mkdir(fp"${payload_root}/usr/lib", parents: true)?
  fs.symlink(p"link", fp"${payload_root}/usr/lib/link")?
  archive.tar_create(prepared.staged.payload, payload_root, [p"."], compression: "gz", overwrite: true)?
  let receipt = store.commit(store_root, prepared.node, prepared.staged)?

  expect_root_error(ctx, root.preflight([receipt]), "root symlink usr/lib/link does not match metadata")?
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
  test.eq(root.compose_artifacts(first_output, first, [alpha, beta])?, root.compose_artifacts(second_output, second, [beta, alpha])?)?
}

proc test_root_coalesces_identical_nested_directories_with_a_canonical_owner(ctx: TestContext) [fs, error] {
  let store_root = test.temp_dir(ctx, name: "root-shared-directories-store")?
  let alpha = commit_artifact(
    ctx,
    store_root,
    "alpha",
    types.Payload,
    [payload_tree("usr", mode: 0o755), payload_tree("usr/share", mode: 0o755), payload_file("usr/share/alpha", "alpha")],
  )?
  let beta = commit_artifact(
    ctx,
    store_root,
    "beta",
    types.Payload,
    [payload_tree("usr", mode: 0o755), payload_tree("usr/share", mode: 0o755), payload_file("usr/share/beta", "beta")],
  )?
  let first = root.preflight([beta, alpha])?
  let second = root.preflight([alpha, beta])?
  test.eq(first, second)?
  test.eq(first.entries.len(), 4)?
  test.eq([entry.path for entry in first.entries], ["usr", "usr/share", "usr/share/alpha", "usr/share/beta"])?
  test.eq([entry.package_name for entry in first.entries if entry.kind == types.Tree], ["alpha", "alpha"])?

  let output = fp"${test.temp_dir(ctx, name: "root-shared-directories-output")?}/root"
  let receipt = root.compose_artifacts(output, first, [beta, alpha])?
  test.eq(receipt.entries, first.entries)?
  test.eq(fp"${output}/usr/share/alpha".read_text()?, "alpha")?
  test.eq(fp"${output}/usr/share/beta".read_text()?, "beta")?
  root.verify(output, receipt)?
}

proc test_root_rejects_collisions_and_same_owner_duplicate_entries_before_mutation(ctx: TestContext) [fs, error] {
  let store_root = test.temp_dir(ctx, name: "root-collision-store")?
  let left = commit_artifact(ctx, store_root, "left", types.Payload, [payload_file("usr/bin/shared", "left")])?
  let right = commit_artifact(ctx, store_root, "right", types.Payload, [payload_file("usr/bin/shared", "right")])?
  expect_root_error(ctx, root.preflight([left, right]), "owned by both")?
  let collision_output = fp"${test.temp_dir(ctx, name: "root-collision-output")?}/root"
  let empty_plan = root.preflight([])?

  match root.compose_artifacts(collision_output, empty_plan, [left, right]) {
    Ok(_) => test.fail("colliding artifacts unexpectedly composed")?
    Err(problem) => test.contains(problem.message, "owned by both")?
  }

  test.eq(fs.exists(collision_output)?, false)?

  let linked_left = commit_artifact(ctx, store_root, "linked-left", types.Payload, [payload_symlink("usr/bin/shared-link", "tool")])?
  let linked_right = commit_artifact(ctx, store_root, "linked-right", types.Payload, [payload_symlink("usr/bin/shared-link", "tool")])?
  expect_root_error(ctx, root.preflight([linked_left, linked_right]), "owned by both")?

  let directory_left = commit_artifact(ctx, store_root, "directory-left", types.Payload, [payload_tree("usr/share/incompatible", mode: 0o755)])?
  let directory_right = commit_artifact(ctx, store_root, "directory-right", types.Payload, [payload_tree("usr/share/incompatible", mode: 0o700)])?
  expect_root_error(ctx, root.preflight([directory_left, directory_right]), "incompatible metadata")?

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

proc test_root_identifies_the_missing_payload_inventory_entry(ctx: TestContext) [fs, error] {
  let store_root = test.temp_dir(ctx, name: "root-missing-entry-store")?
  let staged = stage_artifact(
    ctx,
    "missing-entry",
    types.Payload,
    [payload_file("usr/bin/present", "present"), payload_tree("usr/share")],
  )?
  let archive_root = test.temp_dir(ctx, name: "root-missing-entry-archive")?
  fs.mkdir(fp"${archive_root}/usr/bin", parents: true)?
  fs.write(fp"${archive_root}/usr/bin/present", "present")?
  archive.tar_create(staged.staged.payload, archive_root, [p"."], compression: "gz", overwrite: true)?
  let receipt = store.commit(store_root, staged.node, staged.staged)?

  expect_root_error(
    ctx,
    root.preflight([receipt]),
    "artifact missing-entry payload entry usr/share failed verification: root entry usr/share is absent or unreadable",
  )?
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
  let _ = root.compose_artifacts(output, plan, [app, runtime])?
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

  match root.compose_artifacts(output, plan, [artifact]) {
    Ok(_) => test.fail("completed root was overwritten")?
    Err(problem) => test.contains(problem.message, "already exists")?
  }

  test.eq(fp"${output}/marker".read_text()?, "previous root")?
}
