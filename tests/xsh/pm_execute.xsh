##! Behavior coverage for immutable BuildPlan execution through isolated artifact roots.
use pm.catalog
use pm.execute
use pm.plan
use pm.policy
use pm.store
use pm.types

pure fixture(name: Str) -> Path {
  fp"tests/xsh/fixtures/${name}"
}

pure executor_identity() -> types.ExecutorIdentity {
  {
    format: "laputa-pm-executor-1",
    pm_sha256: "pm-tree",
    xsh_sha256: "xsh-runners",
    core_sha256: "core-tree",
  }
}

pure empty_remote_snapshot() -> types.RemoteSnapshot {
  {target: types.Aarch64LinuxMusl, index_sha256: "execute-empty-remote", packages: []}
}

proc copied_execute_repository(ctx: TestContext, name: Str) [fs, env, error] -> Result[Path] {
  let root = test.temp_dir(ctx, name: name)?
  let _ = fs.copy_tree(fixture("execute/repo"), fp"${root}/repo", parents: true, overwrite: true)?
  fs.mkdir(fp"${root}/pm")?
  fs.copy(p"pm/proof.xsh", fp"${root}/pm/proof.xsh", overwrite: true)?
  root
}

proc resolve_execute_plan_for_roots(repo_root: Path, roots: List[Str]) [fs, env, error] -> Result[types.BuildPlan] {
  let value = catalog.load(repo_root)?
  plan.resolve(value, empty_remote_snapshot(), policy.aarch64_docker(), roots, false, executor_identity())?
}

proc resolve_execute_plan(repo_root: Path) [fs, env, error] -> Result[types.BuildPlan] {
  resolve_execute_plan_for_roots(repo_root, ["execute-app"])?
}

proc node_named(value: types.BuildPlan, name: Str) [error] -> Result[types.PlanNode] {
  for node in value.nodes {
    if node.name == name {
      return node
    }
  }

  return Err(types.PmError.PackageContract(f"missing execute plan node ${name}"))
}

proc receipt_named(value: types.BuildResult, name: Str) [error] -> Result[types.ArtifactReceipt] {
  for receipt in value.artifacts {
    if receipt.package_name == name {
      return receipt
    }
  }

  return Err(types.PmError.PackageContract(f"missing execute result artifact ${name}"))
}

proc execute_store(ctx: TestContext, name: Str) [fs, error] -> Result[Path] {
  test.temp_dir(ctx, name: name)
}

proc write_execute_metapackage(repo_root: Path) [fs, error] {
  let package = fp"${repo_root}/repo/execute-meta"
  fs.mkdir(package)?
  fs.write(
    fp"${package}/PKGBUILD.xsh",
    """##! Executor metapackage fixture without a payload proof.
export let name = "execute-meta"
export let package_kind = "meta"
export let ver = "1.0.0"
export let rel = "1"
export let deps = ["execute-dep"]
export let mkdeps_host = []
export let mkdeps_target = []
export let upstream_sources = []
export let filetree = []
""",
  )?
}

proc write_execute_leaf(repo_root: Path) [fs, error] {
  let package = fp"${repo_root}/repo/execute-leaf"
  fs.mkdir(package)?
  fs.write(
    fp"${package}/PKGBUILD.xsh",
    r"""##! Executor fixture that must not start until execute-app publishes.
export let name = "execute-leaf"
export let package_kind = "payload"
export let ver = "1.0.0"
export let rel = "1"
export let deps = ["execute-app"]
export let mkdeps_host = []
export let mkdeps_target = []
export let upstream_sources = []
export let filetree = [{path: p"usr/share/execute-leaf.txt", kind: "file"}]

export proc build(dest: Path) [fs, env, error] -> Result[Unit] {
  let root = env("LAPUTA_ROOT")?
  let _ = fs.read_text(fp"${root}/usr/share/execute-app.txt")?
  let target = fp"${dest}/usr/share/execute-leaf.txt"
  fs.mkdir(target.parent)?
  fs.write(target, "leaf\\n")?
}
""",
  )?
}

proc exact_remote_snapshot(
  value: types.BuildPlan,
  result: types.BuildResult,
  remote_root: Path,
) [fs, error] -> Result[types.RemoteSnapshot] {
  let executor_sha256 = plan.executor_fingerprint(value.executor)?
  var packages: List[types.RemotePlanArtifact] = []

  for node in value.nodes {
    let receipt = receipt_named(result, node.name)?
    let tarball = fp"${remote_root}/packages/aarch64/${node.name}/${node.package_id}.tar.gz"
    let metadata = fp"${remote_root}/metadata/aarch64/${node.name}/${node.package_id}.json"
    fs.mkdir(tarball.parent)?
    fs.mkdir(metadata.parent)?
    fs.copy(fp"${receipt.artifact_dir}/payload.tar.gz", tarball, overwrite: true)?
    let raw: Record = json.read(fp"${receipt.artifact_dir}/metadata.json")?
    fs.write(metadata, json.encode({...raw, executor_sha256})? + "\n")?
    packages = packages.push({
      name: node.name,
      ver: node.ver,
      rel: node.rel,
      retrieval: {
        arch: "aarch64",
        tarball: tarball.relative_to(remote_root).display(),
        tarball_sha256: hash.sha256(tarball)?.hex(),
        metadata: metadata.relative_to(remote_root).display(),
        metadata_sha256: hash.sha256(metadata)?.hex(),
      },
      artifact_key: node.artifact_key,
      recipe_sha256: node.recipe_sha256,
      executor_sha256,
      proof_key: node.proof_key,
      proof_sha256: node.proof_sha256,
    })
  }

  {target: value.target, index_sha256: "execute-remote-snapshot", packages}
}

proc test_execute_builds_dependency_levels_in_isolated_roots_and_reuses(ctx: TestContext) [fs, net, process, env, time, error] {
  let repo_root = copied_execute_repository(ctx, "execute-build-repo")?
  let value = resolve_execute_plan(repo_root)?
  let object_store = execute_store(ctx, "execute-build-store")?
  let stale = fp"${object_store}/v1/tmp/${node_named(value, "execute-app")?.artifact_key}"
  fs.mkdir(stale)?
  fs.write(fp"${stale}/partial", "interrupted build state")?
  let first = execute.build_plan(value, repo_root, object_store, "", 2)?
  test.eq([node.name for node in value.nodes], ["execute-dep", "execute-tool", "execute-app"])?
  test.eq([receipt.package_name for receipt in first.artifacts], ["execute-dep", "execute-tool", "execute-app"])?
  test.eq([receipt.origin for receipt in first.artifacts], [types.Built, types.Built, types.Built])?
  test.ok(fs.exists(store.artifact_path(object_store, node_named(value, "execute-app")?.artifact_key))?)?
  test.eq(fs.exists(stale)?, false)?
  test.eq(fs.exists(fp"${repo_root}/repo/app/run-package-build.xsh")?, false)?

  # Jobs are a scheduler choice, never a build-plan or artifact-key input.
  let second = execute.build_plan(value, repo_root, object_store, "", 3)?
  test.eq(second, first)?
}

proc test_execute_reproofs_changed_proof_without_rebuilding_payload(ctx: TestContext) [fs, net, process, env, time, error] {
  let repo_root = copied_execute_repository(ctx, "execute-reproof-repo")?
  let object_store = execute_store(ctx, "execute-reproof-store")?
  let initial = resolve_execute_plan(repo_root)?
  let built = execute.build_plan(initial, repo_root, object_store, "", 1)?
  let initial_app = node_named(initial, "execute-app")?
  let initial_receipt = receipt_named(built, "execute-app")?
  let proof_path = fp"${repo_root}/repo/app/proof.xsh"
  fs.write(proof_path, proof_path.read_text()? + "\n# proof revision only\n")?
  let reproved_plan = resolve_execute_plan(repo_root)?
  let reproved_app = node_named(reproved_plan, "execute-app")?
  test.eq(reproved_app.artifact_key, initial_app.artifact_key)?
  test.eq(reproved_app.proof_key == initial_app.proof_key, false)?
  let reproved = execute.build_plan(reproved_plan, repo_root, object_store, "", 2)?
  test.eq(receipt_named(reproved, "execute-app")?, initial_receipt)?
  test.ok(fs.exists(fp"${object_store}/v1/proofs/${reproved_app.artifact_key}/${reproved_app.proof_key}.json")?)?
}

proc test_execute_parallel_level_requires_published_dependency_receipts(ctx: TestContext) [fs, net, process, env, time, error] {
  let repo_root = copied_execute_repository(ctx, "execute-level-barrier-repo")?
  write_execute_leaf(repo_root)?
  let object_store = execute_store(ctx, "execute-level-barrier-store")?
  let app_proof = fp"${repo_root}/repo/app/proof.xsh"
  fs.write(
    app_proof,
    """error ProofError = Failed(message: Str)

proc main(root: Path) [error] {
  return Err(ProofError.Failed("intentional level-one proof failure"))
}

main(@args)?
""",
  )?
  let value = resolve_execute_plan_for_roots(repo_root, ["execute-leaf"])?
  let app = node_named(value, "execute-app")?
  let leaf = node_named(value, "execute-leaf")?
  test.eq(app.level, 1)?
  test.eq(leaf.level, 2)?
  test.eq([dependency.name for dependency in leaf.dependencies], ["execute-app"])?

  # Level zero has independent dep/tool work under two workers. The level-one
  # proof then fails. A dependent level must never run and replace that cause
  # with an absent-artifact error.
  match execute.build_plan(value, repo_root, object_store, "", 2) {
    Ok(_) => test.fail("parallel executor advanced past a failed dependency level")?
    Err(problem) => test.contains(problem.message, "package proof for execute-app")?
  }

  test.eq(fs.exists(store.artifact_path(object_store, app.artifact_key))?, false)?
  test.eq(fs.exists(store.artifact_path(object_store, leaf.artifact_key))?, false)?
}

proc test_execute_rebuilds_changed_recipe_and_dependents(ctx: TestContext) [fs, net, process, env, time, error] {
  let repo_root = copied_execute_repository(ctx, "execute-package-change-repo")?
  let object_store = execute_store(ctx, "execute-package-change-store")?
  let initial = resolve_execute_plan(repo_root)?
  let _ = execute.build_plan(initial, repo_root, object_store, "", 1)?
  let initial_dep = node_named(initial, "execute-dep")?
  let initial_app = node_named(initial, "execute-app")?
  let pkgbuild = fp"${repo_root}/repo/dep/PKGBUILD.xsh"
  fs.write(pkgbuild, pkgbuild.read_text()?.replace("dependency\\n", "dependency revision two\\n"))?
  let changed = resolve_execute_plan(repo_root)?
  let changed_dep = node_named(changed, "execute-dep")?
  let changed_app = node_named(changed, "execute-app")?
  test.eq(changed_dep.artifact_key == initial_dep.artifact_key, false)?
  test.eq(changed_app.artifact_key == initial_app.artifact_key, false)?
  let result = execute.build_plan(changed, repo_root, object_store, "", 1)?
  test.eq(receipt_named(result, "execute-dep")?.key, changed_dep.artifact_key)?
  test.ok(fs.exists(store.artifact_path(object_store, changed_app.artifact_key))?)?
  test.eq(receipt_named(result, "execute-app")?.key, changed_app.artifact_key)?
}

proc test_execute_rebuilds_when_package_source_input_changes(ctx: TestContext) [fs, net, process, env, time, error] {
  let repo_root = copied_execute_repository(ctx, "execute-source-change-repo")?
  let object_store = execute_store(ctx, "execute-source-change-store")?
  let initial = resolve_execute_plan(repo_root)?
  let _ = execute.build_plan(initial, repo_root, object_store, "", 1)?
  let initial_app = node_named(initial, "execute-app")?
  fs.write(fp"${repo_root}/repo/app/files/input.txt", "source revision two\n")?
  let changed = resolve_execute_plan(repo_root)?
  let changed_app = node_named(changed, "execute-app")?
  test.eq(changed_app.artifact_key == initial_app.artifact_key, false)?
  let result = execute.build_plan(changed, repo_root, object_store, "", 1)?
  test.eq(receipt_named(result, "execute-app")?.key, changed_app.artifact_key)?
}

proc test_execute_metapackage_keeps_opaque_marker_and_proves_runtime_dependencies(ctx: TestContext) [fs, net, process, env, time, error] {
  let repo_root = copied_execute_repository(ctx, "execute-meta-repo")?
  write_execute_metapackage(repo_root)?
  let value = resolve_execute_plan_for_roots(repo_root, ["execute-meta"])?
  test.eq([node.name for node in value.nodes], ["execute-dep", "execute-meta"])?
  let object_store = execute_store(ctx, "execute-meta-store")?
  let result = execute.build_plan(value, repo_root, object_store, "", 1)?
  let dependency = receipt_named(result, "execute-dep")?
  let meta = receipt_named(result, "execute-meta")?
  let meta_metadata: Record = json.read(fp"${meta.artifact_dir}/metadata.json")?
  let files = meta_metadata.get("files")?.require(List[Record])?

  # No meta proof script exists. Success therefore proves the executor did not
  # attempt to extract or run the opaque marker, while its runtime dependency
  # still completed the regular proof path first.
  test.eq(fs.read_text(fp"${meta.artifact_dir}/payload.tar.gz")?, "laputa metapackage payload marker\n")?
  test.eq(meta_metadata.get("package_kind")?, "meta")?
  test.eq(files, [])?
  test.ok(fs.exists(fp"${meta.artifact_dir}/proof.json")?)?
  test.ok(fs.exists(fp"${dependency.artifact_dir}/proof.json")?)?
}

proc test_execute_imports_exact_remote_artifacts_without_remote_index_resolution(ctx: TestContext) [fs, net, process, env, time, error] {
  let repo_root = copied_execute_repository(ctx, "execute-remote-repo")?
  let local_plan = resolve_execute_plan(repo_root)?
  let local_store = execute_store(ctx, "execute-remote-local-store")?
  let local_result = execute.build_plan(local_plan, repo_root, local_store, "", 1)?
  let remote_root = test.temp_dir(ctx, name: "execute-remote-objects")?
  let snapshot = exact_remote_snapshot(local_plan, local_result, remote_root)?
  let catalog_value = catalog.load(repo_root)?
  let remote_plan = plan.resolve(catalog_value, snapshot, policy.aarch64_docker(), ["execute-app"], false, executor_identity())?
  test.eq([types.plan_action_text(node.action) for node in remote_plan.nodes], ["reuse-remote", "reuse-remote", "reuse-remote"])?

  let imported_store = execute_store(ctx, "execute-remote-imported-store")?
  let imported = execute.build_plan(remote_plan, repo_root, imported_store, f"file://${remote_root}", 1)?
  test.eq([receipt.origin for receipt in imported.artifacts], [types.Remote, types.Remote, types.Remote])?
  test.eq([receipt.key for receipt in imported.artifacts], [node.artifact_key for node in remote_plan.nodes])?
}

proc test_execute_proof_failure_and_corrupt_final_never_publish_replacement(ctx: TestContext) [fs, net, process, env, time, error] {
  let repo_root = copied_execute_repository(ctx, "execute-proof-failure-repo")?
  let object_store = execute_store(ctx, "execute-proof-failure-store")?
  let proof_path = fp"${repo_root}/repo/app/proof.xsh"
  fs.write(
    proof_path,
    """error ProofError = Failed(message: Str)

proc main(root: Path = /rootfs) [error] {
  return Err(ProofError.Failed(\"intentional proof failure\"))
}

main(@args)?
""",
  )?
  let failed_plan = resolve_execute_plan(repo_root)?
  let failed_app = node_named(failed_plan, "execute-app")?

  match execute.build_plan(failed_plan, repo_root, object_store, "", 1) {
    Ok(_) => test.fail("failed proof unexpectedly published an application artifact")?
    Err(problem) => test.contains(problem.message, "package proof for execute-app")?
  }

  test.eq(fs.exists(store.artifact_path(object_store, failed_app.artifact_key))?, false)?

  let healthy_repo = copied_execute_repository(ctx, "execute-corrupt-repo")?
  let healthy_plan = resolve_execute_plan(healthy_repo)?
  let healthy_store = execute_store(ctx, "execute-corrupt-store")?
  let healthy = execute.build_plan(healthy_plan, healthy_repo, healthy_store, "", 1)?
  let healthy_app = node_named(healthy_plan, "execute-app")?
  let final_dir = store.artifact_path(healthy_store, healthy_app.artifact_key)
  fs.write(fp"${final_dir}/payload.tar.gz", "corrupt final payload")?

  match execute.build_plan(healthy_plan, healthy_repo, healthy_store, "", 1) {
    Ok(_) => test.fail("corrupt final artifact unexpectedly reused or overwritten")?
    Err(problem) => test.contains(problem.message, "payload SHA-256 does not match receipt")?
  }

  test.eq(fs.read_text(fp"${final_dir}/payload.tar.gz")?, "corrupt final payload")?
  test.eq(receipt_named(healthy, "execute-app")?.key, healthy_app.artifact_key)?
}
