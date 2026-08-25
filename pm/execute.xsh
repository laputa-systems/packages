##! Executes one immutable BuildPlan through verified artifact-store receipts and isolated mutable work roots.
# Proof input is intentionally separate from artifact input: a changed proof writes a second immutable
# attestation under `v1/proofs/<artifact-key>/<proof-key>.json` after rechecking the unchanged payload.
use build as pm_build
use fingerprint
use local
use plan as build_plan
use proof as pm_proof
use recipe
use root as pm_root
use sources
use store
use types
use util

pure execute_proof_cache_path(store_root: Path, artifact_key: Str, proof_key: Str) -> Path {
  fp"${store_root}/v1/proofs/${artifact_key}/${proof_key}.json"
}

proc execute_executor_digest(plan_value: types.BuildPlan) [error] -> Result[Str] {
  build_plan.executor_fingerprint(plan_value.executor)?
}

proc execute_load_package(
  plan_value: types.BuildPlan,
  node: types.PlanNode,
  repo_root: Path,
) [fs, env, error] -> Result[types.Package] {
  let relative = util.ensure_relative_path(node.recipe_dir, f"plan recipe directory for ${node.name}")?
  let pkg = recipe.load_package(fp"${repo_root}/${relative}")?

  if pkg.name != node.name or pkg.ver != node.ver or pkg.rel != node.rel or util.package_id(pkg.name, pkg.ver, pkg.rel) != node.package_id {
    return Err(types.PmError.PackageContract(f"recipe ${node.recipe_dir.display()} does not match plan node ${node.package_id}"))
  }

  if fingerprint.package_build_input(repo_root, pkg, plan_value.target)? != node.recipe_sha256 {
    return Err(types.PmError.PackageContract(f"recipe build input changed after plan creation for ${node.package_id}"))
  }

  if fingerprint.package_proof_input(repo_root, pkg)? != node.proof_sha256 {
    return Err(types.PmError.PackageContract(f"recipe proof input changed after plan creation for ${node.package_id}"))
  }

  pkg
}

proc execute_require_receipt(
  plan_value: types.BuildPlan,
  node: types.PlanNode,
  receipt: types.ArtifactReceipt,
) [error] {
  let expected_executor = execute_executor_digest(plan_value)?
  let expected_dependencies = [dependency.artifact_key for dependency in node.dependencies]
  let expected_runtime_dependencies = [dependency.artifact_key for dependency in node.dependencies if dependency.kind == types.Runtime]

  if receipt.key != node.artifact_key or receipt.package_name != node.name or receipt.package_id != node.package_id or receipt.recipe_sha256 != node.recipe_sha256 or receipt.executor_sha256 != expected_executor or receipt.dependency_keys != expected_dependencies or receipt.runtime_dependency_keys != expected_runtime_dependencies {
    return Err(types.PmError.PackageContract(f"stored artifact ${node.artifact_key} does not match plan node ${node.package_id}"))
  }
}

proc execute_receipt_closure(store_root: Path, keys: List[Str]) [fs, error] -> Result[List[types.ArtifactReceipt]] {
  var pending = keys |> sort
  var index = 0
  var seen: Map[Bool] = {}
  var receipts: List[types.ArtifactReceipt] = []

  while index < pending.len() {
    let key = pending[index]
    index += 1

    if seen.get(key, false) {
      continue
    }

    let receipt = store.lookup(store_root, key)?
    seen[key] = true
    receipts = receipts.push(receipt)

    for runtime_key in receipt.runtime_dependency_keys |> sort {
      if ! seen.get(runtime_key, false) {
        pending = pending.push(runtime_key)
      }
    }
  }

  receipts |> sort-by .package_name
}

proc execute_mutable_root(
  root_handle: FsRoot,
  label: Str,
  artifacts: List[types.ArtifactReceipt],
) [fs, process, env, error] -> Result[Path] {
  let work = fs.root_path(root_handle)?
  let immutable = fp"${work}/${label}-dependencies"
  let mutable = fp"${work}/${label}-work"
  let root_plan = pm_root.preflight(artifacts)?
  let _ = pm_root.compose(immutable, root_plan, artifacts)?
  let _ = fs.copy_tree(immutable, mutable, parents: true, overwrite: true)?
  pm_build.seed_executor_substrate(mutable)?
  mutable
}

proc execute_stage_local(
  plan_value: types.BuildPlan,
  node: types.PlanNode,
  pkg: types.Package,
  build_root: Path,
  work: Path,
) [fs, net, process, env, time, error] -> Result[types.StagedArtifact] {
  let recipe_dir = fp"${work}/recipe"
  let source = fp"${work}/source"
  let dest = fp"${work}/dest"
  let payload = fp"${work}/payload.tar.gz"
  let metadata = fp"${work}/metadata.json"
  let proof = fp"${work}/proof.json"
  # build_prepared_package creates a traced dynamic runner beside its recipe. Keep that implementation
  # detail inside this node's work tree so execution never writes the checkout or another node's recipe.
  let _ = fs.copy_tree(pkg.dir, recipe_dir, parents: true, overwrite: true)?
  let isolated_pkg = {...pkg, dir: recipe_dir}
  fs.mkdir(source)?
  sources.prepare_package_source_tree(work, work, isolated_pkg, source, false, false, false)?

  env {
    LAPUTA_ROOT = build_root.display()
    PATH = f"${build_root}/bin:${build_root}/usr/bin:${env.get("PATH") ?? ""}"
    XSH_PM_BUILD_CHROOT = "0"
  } {
    pm_build.build_prepared_package(recipe_dir, source, dest, payload)?
  } ?

  let built = local.load_built_package_from_dest(isolated_pkg, node.package_id, payload, dest)?
  local.write_package_metadata(metadata, "aarch64", built)?
  pm_proof.write_artifact_receipt(proof, node, payload)?
  {payload, metadata, proof, executor_sha256: execute_executor_digest(plan_value)?}
}

proc execute_cached_proof_is_valid(
  store_root: Path,
  node: types.PlanNode,
  payload: Path,
) [fs, error] -> Result[Bool] {
  let cached = execute_proof_cache_path(store_root, node.artifact_key, node.proof_key)

  if ! fs.exists(cached)? {
    return false
  }

  pm_proof.verify_artifact_receipt(cached, node, payload)?
  true
}

proc execute_publish_proof_cache(
  store_root: Path,
  node: types.PlanNode,
  payload: Path,
  proof: Path,
) [fs, error] {
  pm_proof.verify_artifact_receipt(proof, node, payload)?
  let cached = execute_proof_cache_path(store_root, node.artifact_key, node.proof_key)
  fs.mkdir(cached.parent)?
  let lock = fs.lock(fp"${cached.parent}/${node.proof_key}.lock")?
  defer fs.unlock(lock)?

  if fs.exists(cached)? {
    pm_proof.verify_artifact_receipt(cached, node, payload)?
    return
  }

  let temporary = fp"${cached}.tmp"
  fs.remove(temporary, missing_ok: true)?
  defer fs.remove(temporary, missing_ok: true)?
  fs.copy(proof, temporary, overwrite: true)?
  fs.rename(temporary, cached)?
  pm_proof.verify_artifact_receipt(cached, node, payload)?
}

proc execute_run_proof(
  node: types.PlanNode,
  pkg: types.Package,
  store_root: Path,
  payload: Path,
  proof: Path,
) [fs, process, env, error] {
  if execute_cached_proof_is_valid(store_root, node, payload)? {
    return
  }

  let runtime_keys = [dependency.artifact_key for dependency in node.dependencies if dependency.kind == types.Runtime]
  let runtime_artifacts = execute_receipt_closure(store_root, runtime_keys)?
  let root_handle = fs.tempdir()?
  defer fs.close_root(root_handle)?
  let proof_root = execute_mutable_root(root_handle, "proof", runtime_artifacts)?
  archive.tar_extract(payload, proof_root, 0, "auto", true)?
  pm_proof.run_artifact_proof(proof_root, pkg)?
  pm_proof.write_artifact_receipt(proof, node, payload)?
  execute_publish_proof_cache(store_root, node, payload, proof)?
}

proc execute_build_local(
  plan_value: types.BuildPlan,
  node: types.PlanNode,
  repo_root: Path,
  store_root: Path,
) [fs, net, process, env, time, error] -> Result[types.ArtifactReceipt] {
  let pkg = execute_load_package(plan_value, node, repo_root)?
  let dependency_keys = [dependency.artifact_key for dependency in node.dependencies]
  let dependencies = execute_receipt_closure(store_root, dependency_keys)?
  let root_handle = fs.tempdir()?
  defer fs.close_root(root_handle)?
  let build_root = execute_mutable_root(root_handle, "build", dependencies)?
  let work = fs.root_path(root_handle)?
  let staged = execute_stage_local(plan_value, node, pkg, build_root, work)?
  execute_run_proof(node, pkg, store_root, staged.payload, staged.proof)?
  let receipt = store.commit(store_root, node, staged)?
  execute_require_receipt(plan_value, node, receipt)?
  execute_publish_proof_cache(store_root, node, fp"${receipt.artifact_dir}/payload.tar.gz", staged.proof)?
  receipt
}

proc execute_existing_local(
  plan_value: types.BuildPlan,
  node: types.PlanNode,
  repo_root: Path,
  store_root: Path,
) [fs, process, env, error] -> Result[types.ArtifactReceipt] {
  let receipt = store.lookup(store_root, node.artifact_key)?
  execute_require_receipt(plan_value, node, receipt)?

  if receipt.proof_key == node.proof_key and receipt.proof_sha256 == node.proof_sha256 {
    return receipt
  }

  let pkg = execute_load_package(plan_value, node, repo_root)?
  let root_handle = fs.tempdir()?
  defer fs.close_root(root_handle)?
  let work = fs.root_path(root_handle)?
  let proof = fp"${work}/proof.json"
  execute_run_proof(node, pkg, store_root, fp"${receipt.artifact_dir}/payload.tar.gz", proof)?
  receipt
}

proc execute_remote_node(
  plan_value: types.BuildPlan,
  node: types.PlanNode,
  store_root: Path,
  remote_repo: Str,
) [fs, net, error] -> Result[types.ArtifactReceipt] {
  if node.remote == null {
    return Err(types.PmError.PackageContract(f"remote plan node ${node.package_id} has no immutable retrieval coordinates"))
  }

  let cache_handle = fs.tempdir()?
  defer fs.close_root(cache_handle)?
  let cache = fs.root_path(cache_handle)?
  let receipt = store.import_remote(store_root, node, remote_repo, cache)?
  execute_require_receipt(plan_value, node, receipt)?
  receipt
}

## Executes one exact BuildPlan node using only verified dependency artifacts from the immutable store.
export proc build_node(
  plan_value: types.BuildPlan,
  node: types.PlanNode,
  repo_root: Path,
  store_root: Path,
  remote_repo: Str,
) [fs, net, process, env, time, error] -> Result[types.ArtifactReceipt] {
  build_plan.validate(plan_value)?

  if fs.exists(store.artifact_path(store_root, node.artifact_key))? {
    return execute_existing_local(plan_value, node, repo_root, store_root)
  }

  match node.action {
    types.ReuseRemote(_) => execute_remote_node(plan_value, node, store_root, remote_repo)?
    types.Build(_) => execute_build_local(plan_value, node, repo_root, store_root)?
  }
}

## Executes each topological BuildPlan level with bounded, deterministic result ordering; artifact-store receipts are the only resume state.
export proc build_plan(
  plan_value: types.BuildPlan,
  repo_root: Path,
  store_root: Path,
  remote_repo: Str,
  jobs: Int,
) [fs, net, process, env, time, error] -> Result[types.BuildResult] {
  build_plan.validate(plan_value)?

  if jobs < 1 {
    return Err(types.PmError.Usage("build jobs must be at least one"))
  }

  var artifacts: List[types.ArtifactReceipt] = []
  var index = 0

  while index < plan_value.nodes.len() {
    let level = plan_value.nodes[index].level
    var level_nodes: List[types.PlanNode] = []

    while index < plan_value.nodes.len() and plan_value.nodes[index].level == level {
      level_nodes = level_nodes.push(plan_value.nodes[index])
      index += 1
    }

    if jobs == 1 or level_nodes.len() == 1 {
      for node in level_nodes {
        artifacts = artifacts.push(build_node(plan_value, node, repo_root, store_root, remote_repo)?)
      }
    } else {
      # par-map preserves ordinal result order, while every node owns a fresh root and artifact key lock.
      let completed = level_nodes
        |> par-map --jobs=jobs { |node| build_node(plan_value, node, repo_root, store_root, remote_repo) }
        |> collect()

      for result in completed {
        artifacts = artifacts.push(result)
      }
    }
  }

  {format: "laputa-build-result-1", plan_sha256: plan_value.plan_sha256, artifacts}
}
