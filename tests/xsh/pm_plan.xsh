##! Behavior coverage for exact package and executor semantic fingerprints.
use pm.fingerprint
use pm.recipe
use pm.types
use pm.catalog
use pm.plan
use pm.plan_json
use pm.policy

pure fixture(name: Str) -> Path {
  fp"tests/xsh/fixtures/${name}"
}

proc copied_package(ctx: TestContext, name: Str) [fs, env, error] -> Result[types.Package] {
  let dir = test.temp_dir(ctx, name: name)?
  let _ = fs.copy_tree(fixture("fingerprint-package"), dir, parents: true, overwrite: true)?
  recipe.load_package(dir)?
}

proc copied_executor(ctx: TestContext) [fs, error] -> Result[Path] {
  let root = test.temp_dir(ctx, name: "fingerprint-executor")?
  let _ = fs.copy_tree(fixture("fingerprint-executor"), root, parents: true, overwrite: true)?
  root
}

proc build_input(pkg: types.Package) [fs, error] -> Result[Str] {
  fingerprint.package_build_input(p".", pkg, types.Aarch64LinuxMusl)?
}

test test_package_build_fingerprint_is_repeatable_and_ignores_mtime [fs, env, error] { |ctx|
  let pkg = copied_package(ctx, "fingerprint-repeat")?
  let first = build_input(pkg)?
  test.eq(build_input(pkg)?, first)?
  let helper = fp"${pkg.dir}/helper.xsh"
  fs.write(helper, helper.read_text()?)?
  test.eq(build_input(pkg)?, first)?
}

test test_x86_build_fingerprint_uses_x86_source_checksum [fs, env, error] { |ctx|
  let pkg = copied_package(ctx, "fingerprint-x86-source")?
  let source = pkg.upstream_sources[0]
  let arm_checksum = {arch: "aarch64", sha256: "arm-source"}
  let x86_checksum = {arch: "x86_64", sha256: "x86-source"}
  let selected = {...pkg, upstream_sources: [{...source, checksums: [arm_checksum, x86_checksum]}]}
  let baseline = fingerprint.package_build_input(p".", selected, types.target_x86_64())?
  let arm_changed = {...selected, upstream_sources: [{...source, checksums: [{...arm_checksum, sha256: "changed-arm"}, x86_checksum]}]}
  let x86_changed = {...selected, upstream_sources: [{...source, checksums: [arm_checksum, {...x86_checksum, sha256: "changed-x86"}]}]}

  test.eq(fingerprint.package_build_input(p".", arm_changed, types.target_x86_64())?, baseline)?
  test.eq(fingerprint.package_build_input(p".", x86_changed, types.target_x86_64())? == baseline, false)?
}

test test_package_build_fingerprint_changes_for_pkgbuild [fs, env, error] { |ctx|
  let pkg = copied_package(ctx, "fingerprint-pkgbuild")?
  let first = build_input(pkg)?
  let pkgbuild = fp"${pkg.dir}/PKGBUILD.xsh"
  fs.write(pkgbuild, pkgbuild.read_text()?.replace("1.0.0", "1.0.1"))?
  test.eq(build_input(pkg)? == first, false)?
}

test test_package_build_fingerprint_changes_for_helper_module [fs, env, error] { |ctx|
  let pkg = copied_package(ctx, "fingerprint-helper")?
  let first = build_input(pkg)?
  fs.write(fp"${pkg.dir}/helper.xsh", "changed helper\n")?
  test.eq(build_input(pkg)? == first, false)?
}

test test_package_build_fingerprint_changes_for_files_tree [fs, env, error] { |ctx|
  let pkg = copied_package(ctx, "fingerprint-files")?
  let first = build_input(pkg)?
  fs.write(fp"${pkg.dir}/files/input.txt", "changed input\n")?
  test.eq(build_input(pkg)? == first, false)?
}

test test_package_build_fingerprint_changes_for_service [fs, env, error] { |ctx|
  let pkg = copied_package(ctx, "fingerprint-service")?
  let first = build_input(pkg)?
  fs.write(fp"${pkg.dir}/service.xsh", "changed service\n")?
  test.eq(build_input(pkg)? == first, false)?
}

test test_proof_fingerprint_is_independent_from_build_input [fs, env, error] { |ctx|
  let pkg = copied_package(ctx, "fingerprint-proof")?
  let build_before = build_input(pkg)?
  let proof_before = fingerprint.package_proof_input(p".", pkg)?
  fs.write(fp"${pkg.dir}/proof.xsh", "changed proof\n")?
  test.eq(build_input(pkg)?, build_before)?
  test.eq(fingerprint.package_proof_input(p".", pkg)? == proof_before, false)?
}

test test_pm_tree_fingerprint_changes_for_implementation [fs, error] { |ctx|
  let root = copied_executor(ctx)?
  let first = fingerprint.pm_tree(root)?
  fs.write(fp"${root}/pm/build.xsh", "changed implementation\n")?
  test.eq(fingerprint.pm_tree(root)? == first, false)?
}

test test_core_tree_fingerprint_changes_for_applet [fs, error] { |ctx|
  let root = copied_executor(ctx)?
  let first = fingerprint.core_tree(fp"${root}/core")?
  fs.write(fp"${root}/core/applet.xsh", "changed applet\n")?
  test.eq(fingerprint.core_tree(fp"${root}/core")? == first, false)?
}

test test_runner_fingerprint_changes_for_runner_bytes [fs, error] { |ctx|
  let root = copied_executor(ctx)?
  let runners = fp"${root}/runners"
  let first = fingerprint.runners(fp"${runners}/xsh", fp"${runners}/xshi", fp"${runners}/xsht")?
  fs.write(fp"${runners}/xshi", "changed xshi\n")?
  test.eq(fingerprint.runners(fp"${runners}/xsh", fp"${runners}/xshi", fp"${runners}/xsht")? == first, false)?
}

test test_package_fingerprint_ignores_absolute_checkout_path [fs, env, error] { |ctx|
  let first = copied_package(ctx, "fingerprint-checkout-a")?
  let second = copied_package(ctx, "fingerprint-checkout-b")?
  test.eq(build_input(first)?, build_input(second)?)
}

pure plan_executor_identity() -> types.ExecutorIdentity {
  {
    format: "laputa-pm-executor-1",
    pm_sha256: "pm-tree",
    xsh_sha256: "xsh-runners",
    core_sha256: "core-tree",
  }
}

pure empty_remote_snapshot() -> types.RemoteSnapshot {
  {target: types.Aarch64LinuxMusl, index_sha256: "remote-index", packages: []}
}

proc copied_plan_repository(ctx: TestContext, name: Str) [fs, env, error] -> Result[Path] {
  let root = test.temp_dir(ctx, name: name)?
  let _ = fs.copy_tree(fixture("graph-catalog/repo"), fp"${root}/repo", parents: true, overwrite: true)?
  fs.mkdir(fp"${root}/pm")?
  fs.copy(p"pm/proof.xsh", fp"${root}/pm/proof.xsh", overwrite: true)?
  root
}

proc plan_catalog(ctx: TestContext, name: Str) [fs, env, error] -> Result[types.PackageCatalog] {
  catalog.load(copied_plan_repository(ctx, name)?)?
}

proc resolve_plan(
  value: types.PackageCatalog,
  roots: List[Str],
  snapshot: types.RemoteSnapshot,
) [fs, error] -> Result[types.BuildPlan] {
  plan.resolve(value, snapshot, policy.aarch64_docker(), roots, false, plan_executor_identity())?
}

pure retrieval_for(name: Str, ver: Str, rel: Str) -> types.RemoteRetrieval {
  {
    arch: "aarch64",
    tarball: f"packages/aarch64/${name}/${name}-${ver}-${rel}.tar.gz",
    tarball_sha256: f"payload-${name}-${ver}-${rel}",
    metadata: f"metadata/aarch64/${name}/${name}-${ver}-${rel}.json",
    metadata_sha256: f"metadata-${name}-${ver}-${rel}",
  }
}

pure plan_test_sha256(value: Str) -> Str {
  bytes.from_text(value).sha256().hex()
}

pure legacy_retrieval_for(name: Str, ver: Str, rel: Str) -> types.RemoteRetrieval {
  {
    arch: "aarch64",
    tarball: f"packages/aarch64/${name}/${name}-${ver}-${rel}.tar.gz",
    tarball_sha256: plan_test_sha256(f"legacy payload ${name}-${ver}-${rel}"),
    metadata: f"metadata/aarch64/${name}/${name}-${ver}-${rel}.json",
    metadata_sha256: plan_test_sha256(f"legacy metadata ${name}-${ver}-${rel}"),
  }
}

proc exact_remote_snapshot(value: types.BuildPlan) [error] -> Result[types.RemoteSnapshot] {
  var packages: List[types.RemotePlanArtifact] = []
  let executor_sha256 = plan.executor_fingerprint(value.executor)?

  for node in value.nodes {
    packages = packages.push({
      name: node.name,
      ver: node.ver,
      rel: node.rel,
      retrieval: retrieval_for(node.name, node.ver, node.rel),
      artifact_key: node.artifact_key,
      recipe_sha256: node.recipe_sha256,
      executor_sha256,
      proof_key: node.proof_key,
      proof_sha256: node.proof_sha256,
    })
  }

  {target: value.target, index_sha256: "remote-index", packages}
}

proc node_named(value: types.BuildPlan, name: Str) [error] -> Result[types.PlanNode] {
  for node in value.nodes {
    if node.name == name {
      return node
    }
  }

  return Err(types.PmError.PackageContract(f"missing plan node ${name}"))
}

pure snapshot_replace(
  value: types.RemoteSnapshot,
  name: Str,
  replacement: types.RemotePlanArtifact,
) -> types.RemoteSnapshot {
  {...value, packages: [if item.name == name { replacement } else { item } for item in value.packages]}
}

proc expect_plan_rejection(ctx: TestContext, value: types.BuildPlan, expected: Str) [fs, error] {
  let path_value = fp"${test.temp_dir(ctx, name: "invalid-plan")?}/plan.json"
  plan_json.write_plan(path_value, value)?
  let raw = json.read(path_value)?.require(plan_json.BuildPlanDto)?
  let nodes = raw.nodes
  let duplicate = {...raw, nodes: nodes.push(nodes[0])}
  fs.write(path_value, json.encode(duplicate)?)?

  match plan_json.read(path_value) {
    Ok(_) => test.fail(f"${expected}: malformed plan unexpectedly loaded")?
    Err(problem) => { assert expected in problem.message }
  }
}

test test_build_plan_is_deterministic_and_has_dependency_first_order [fs, env, error] { |ctx|
  let value = plan_catalog(ctx, "plan-deterministic")?
  let first = resolve_plan(value, ["app"], empty_remote_snapshot())?
  let second = resolve_plan(value, ["app"], empty_remote_snapshot())?
  test.eq(first, second)?
  test.eq(first.roots, ["app"])?
  test.eq([node.name for node in first.nodes], ["host-tool", "runtime-lib", "target-sdk", "app"])?
  test.eq([node.level for node in first.nodes], [0, 0, 0, 1])?
  test.eq(types.plan_action_text(node_named(first, "app")?.action), "build")?
  test.eq(types.plan_action_reason(node_named(first, "app")?.action), "new package")?
}

test test_build_plan_all_roots_are_canonical [fs, env, error] { |ctx|
  let value = plan_catalog(ctx, "plan-all")?
  let first = plan.resolve(value, empty_remote_snapshot(), policy.aarch64_docker(), ["target-sdk", "app"], true, plan_executor_identity())?
  let second = plan.resolve(value, empty_remote_snapshot(), policy.aarch64_docker(), ["app"], true, plan_executor_identity())?
  test.eq(first, second)?
  test.eq(first.roots, ["app", "host-tool", "runtime-lib", "target-sdk"])?
}

test test_build_plan_is_checkout_independent [fs, env, error] { |ctx|
  let first = resolve_plan(plan_catalog(ctx, "plan-checkout-a")?, ["app"], empty_remote_snapshot())?
  let second = resolve_plan(plan_catalog(ctx, "plan-checkout-b")?, ["app"], empty_remote_snapshot())?
  test.eq(first, second)?
}

test test_build_plan_reuses_exact_remote_and_carries_retrieval [fs, env, error] { |ctx|
  let value = plan_catalog(ctx, "plan-remote-exact")?
  let initial = resolve_plan(value, ["app"], empty_remote_snapshot())?
  let reused = resolve_plan(value, ["app"], exact_remote_snapshot(initial)?)?
  let app = node_named(reused, "app")?
  test.eq(types.plan_action_text(app.action), "reuse-remote")?
  test.eq(types.plan_action_reason(app.action), "exact remote artifact")?
  test.ok(app.remote != null)?
  test.eq(app.artifact_key, node_named(initial, "app")?.artifact_key)?
}

test test_build_plan_marks_only_retrieval_derived_remote_keys_as_legacy [fs, env, error] { |ctx|
  let value = plan_catalog(ctx, "plan-legacy-remote")?
  let initial = resolve_plan(value, ["app"], empty_remote_snapshot())?
  let app = node_named(initial, "app")?
  let legacy_packages: List[types.RemotePlanArtifact] = [
    {
      name: node.name,
      ver: node.ver,
      rel: node.rel,
      retrieval: legacy_retrieval_for(node.name, node.ver, node.rel),
      artifact_key: "",
      recipe_sha256: "",
      executor_sha256: "",
      proof_key: "",
      proof_sha256: "",
    }
    for node in initial.nodes
  ]
  let legacy = {
    target: types.Aarch64LinuxMusl,
    index_sha256: "legacy-remote-index",
    packages: legacy_packages,
  }
  let resolved = resolve_plan(value, ["app"], legacy)?
  test.ok(plan.node_uses_legacy_remote_identity(resolved, node_named(resolved, "app")?)?)?
  test.eq(plan.node_uses_legacy_remote_identity(initial, app)?, false)?
}

test test_build_plan_reports_tuple_reasons_and_rejects_behind_remote [fs, env, error] { |ctx|
  let value = plan_catalog(ctx, "plan-reasons")?
  let initial = resolve_plan(value, ["runtime-lib"], empty_remote_snapshot())?
  let snapshot = exact_remote_snapshot(initial)?
  let remote = snapshot.packages[0]
  let older = snapshot_replace(snapshot, "runtime-lib", {...remote, ver: "0"})
  let lower_release = snapshot_replace(snapshot, "runtime-lib", {...remote, rel: "0"})
  let newer = snapshot_replace(snapshot, "runtime-lib", {...remote, ver: "2"})
  let version_build = resolve_plan(value, ["runtime-lib"], older)?
  let release_build = resolve_plan(value, ["runtime-lib"], lower_release)?
  test.eq(types.plan_action_reason(node_named(version_build, "runtime-lib")?.action), "local version differs from remote 0-1")?
  test.eq(types.plan_action_reason(node_named(release_build, "runtime-lib")?.action), "local release is above remote 1-0")?

  match resolve_plan(value, ["runtime-lib"], newer) {
    Ok(_) => test.fail("behind remote tuple unexpectedly planned")?
    Err(problem) => { assert "behind remote 2-1" in problem.message }
  }
}

test test_build_plan_propagates_dependency_keys [fs, env, error] { |ctx|
  let value = plan_catalog(ctx, "plan-propagation")?
  let initial = resolve_plan(value, ["app"], empty_remote_snapshot())?
  var changed: List[types.Package] = []

  for pkg in value.packages {
    changed = changed.push(if pkg.name == "runtime-lib" { {...pkg, rel: "2"} } else { pkg })
  }

  let changed_catalog = catalog.from_packages(value.root, changed)?
  let rebuilt = resolve_plan(changed_catalog, ["app"], empty_remote_snapshot())?
  test.eq(node_named(initial, "runtime-lib")?.artifact_key == node_named(rebuilt, "runtime-lib")?.artifact_key, false)?
  test.eq(node_named(initial, "app")?.artifact_key == node_named(rebuilt, "app")?.artifact_key, false)?
}

test test_build_plan_keeps_same_package_dependency_edges_by_kind [fs, env, error] { |ctx|
  let original = plan_catalog(ctx, "plan-edge-kinds")?
  var packages: List[types.Package] = []

  for pkg in original.packages {
    packages = packages.push(
      if pkg.name == "app" { {...pkg, mkdeps_host: pkg.mkdeps_host.push("runtime-lib")} } else { pkg },
    )
  }

  let value = catalog.from_packages(original.root, packages)?
  let resolved = resolve_plan(value, ["app"], empty_remote_snapshot())?
  let app = node_named(resolved, "app")?
  let runtime_edges = [dependency for dependency in app.dependencies if dependency.name == "runtime-lib"]
  test.eq([types.dependency_kind_text(dependency.kind) for dependency in runtime_edges], ["build-host", "runtime"])?
  test.eq(runtime_edges[0].artifact_key, runtime_edges[1].artifact_key)?

  let repeated = {...app, dependencies: app.dependencies.push(app.dependencies[0])}
  let malformed = {...resolved, nodes: [if node.name == "app" { repeated } else { node } for node in resolved.nodes]}

  match plan.fingerprint(malformed) {
    Ok(_) => test.fail("same-kind duplicate dependency unexpectedly validated")?
    Err(problem) => {
      let problem_message = problem.message
      assert f"repeats ${types.dependency_kind_text(app.dependencies[0].kind)} dependency ${app.dependencies[0].name}" in problem_message
    }
  }
}

test test_build_plan_requires_release_bump_for_changed_dependency [fs, env, error] { |ctx|
  let value = plan_catalog(ctx, "plan-release-bump")?
  let initial = resolve_plan(value, ["app"], empty_remote_snapshot())?
  let snapshot = exact_remote_snapshot(initial)?
  let runtime = node_named(initial, "runtime-lib")?
  let changed_runtime = {
    name: runtime.name,
    ver: runtime.ver,
    rel: runtime.rel,
    retrieval: retrieval_for(runtime.name, runtime.ver, runtime.rel),
    artifact_key: "changed-remote-artifact",
    recipe_sha256: runtime.recipe_sha256,
    executor_sha256: plan.executor_fingerprint(initial.executor)?,
    proof_key: runtime.proof_key,
    proof_sha256: runtime.proof_sha256,
  }

  match resolve_plan(value, ["app"], snapshot_replace(snapshot, "runtime-lib", changed_runtime)) {
    Ok(_) => test.fail("dependent without release bump unexpectedly reused")?
    Err(problem) => { assert "app dependencies changed (runtime-lib); bump PKGBUILD.xsh rel" in problem.message }
  }
}

test test_build_plan_json_round_trip_and_detects_corruption [fs, env, error] { |ctx|
  let value = resolve_plan(plan_catalog(ctx, "plan-json")?, ["app"], empty_remote_snapshot())?
  let path_value = fp"${test.temp_dir(ctx, name: "plan-json-out")?}/basic-aarch64.json"
  let repeat_path = fp"${test.temp_dir(ctx, name: "plan-json-repeat")?}/basic-aarch64.json"
  plan_json.write_plan(path_value, value)?
  plan_json.write_plan(repeat_path, value)?
  test.eq(plan_json.read(path_value)?, value)?

  let original = path_value.read_text()?
  test.eq(repeat_path.read_text()?, original)?
  test.eq(original, fixture("plans/basic-aarch64.json").read_text()?)?
  fs.write(path_value, original.replace("laputa-build-plan-1", "unknown-build-plan"))?

  match plan_json.read(path_value) {
    Ok(_) => test.fail("unknown plan format unexpectedly loaded")?
    Err(problem) => { assert "unsupported build plan format unknown-build-plan" in problem.message }
  }

  fs.write(path_value, original.replace(value.repository_digest, "corrupt-repository-digest"))?

  match plan_json.read(path_value) {
    Ok(_) => test.fail("corrupt plan digest unexpectedly loaded")?
    Err(problem) => { assert "digest does not match" in problem.message }
  }
}

test test_build_plan_json_rejects_duplicate_nodes [fs, env, error] { |ctx|
  expect_plan_rejection(ctx, resolve_plan(plan_catalog(ctx, "plan-duplicate")?, ["app"], empty_remote_snapshot())?, "duplicate node host-tool")?
}

test test_build_plan_json_rejects_dependency_key_mismatch [fs, env, error] { |ctx|
  let value = resolve_plan(plan_catalog(ctx, "plan-dependency-key")?, ["app"], empty_remote_snapshot())?
  let path_value = fp"${test.temp_dir(ctx, name: "plan-dependency-key")?}/plan.json"
  plan_json.write_plan(path_value, value)?
  let raw = json.read(path_value)?.require(plan_json.BuildPlanDto)?
  let original_nodes = raw.nodes
  var nodes = []

  for node in original_nodes {
    let name = node.name

    if name == "app" {
      let dependencies = node.dependencies
      let dependency = dependencies[0]
      nodes = nodes.push({...node, dependencies: [{...dependency, artifact_key: "tampered"}]})
    } else {
      nodes = nodes.push(node)
    }
  }

  fs.write(path_value, json.encode({...raw, nodes})?)?

  match plan_json.read(path_value) {
    Ok(_) => test.fail("dependency key mismatch unexpectedly loaded")?
    Err(problem) => { assert "dependency host-tool artifact key does not match its referenced node" in problem.message }
  }
}

test test_build_plan_normalizes_target_aliases_and_rejects_reserved_target [fs, env, error] { |ctx|
  test.eq(types.parse_target("arm64")?, types.Aarch64LinuxMusl)?
  test.eq(types.parse_target("amd64")?, types.X86_64LinuxMusl)?
  let value = plan_catalog(ctx, "plan-target")?
  let unsupported = {...policy.aarch64_docker(), target: types.TargetReserved}

  match plan.resolve(value, empty_remote_snapshot(), unsupported, ["app"], false, plan_executor_identity()) {
    Ok(_) => test.fail("unsupported target unexpectedly planned")?
    Err(problem) => { assert "unsupported target" in problem.message }
  }
}
