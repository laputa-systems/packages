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
  let expected_dependencies = store.receipt_dependency_keys(node)
  let expected_runtime_dependencies = store.receipt_runtime_dependency_keys(node)

  if receipt.key != node.artifact_key or receipt.package_name != node.name or receipt.package_id != node.package_id or receipt.recipe_sha256 != node.recipe_sha256 or receipt.dependency_keys != expected_dependencies or receipt.runtime_dependency_keys != expected_runtime_dependencies {
    return Err(types.PmError.PackageContract(f"stored artifact ${node.artifact_key} does not match plan node ${node.package_id}"))
  }

  if ! build_plan.node_uses_legacy_remote_identity(plan_value, node)? and receipt.executor_sha256 != expected_executor {
    return Err(types.PmError.PackageContract(f"stored artifact ${node.artifact_key} executor does not match plan node ${node.package_id}"))
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
  seed_executor: Bool,
) [fs, process, env, error] -> Result[Path] {
  let work = fs.root_path(root_handle)?
  let immutable = fp"${work}/${label}-dependencies"
  let mutable = fp"${work}/${label}-work"
  let root_plan = pm_root.preflight(artifacts)?
  let _ = pm_root.compose_artifacts(immutable, root_plan, artifacts)?
  let _ = fs.copy_tree(immutable, mutable, parents: true, overwrite: true)?
  # Only compilation receives the host executor substrate.  A proof root is a
  # target runtime closure; leaking /bin and /usr from the runner both masks
  # missing dependencies and conflicts with baselayout's owned symlinks.
  if seed_executor {
    pm_build.seed_executor_substrate(mutable)?
  }
  mutable
}

proc execute_stage_local(
  plan_value: types.BuildPlan,
  node: types.PlanNode,
  pkg: types.Package,
  repo_root: Path,
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
  # Package recipes may explicitly name repository-owned inputs (for example
  # laputa-pm's PM entrypoint/tree). Resolve those against the plan repository
  # while the recipe itself remains isolated under `work/recipe`.
  env {
    XSH_PM_REPOSITORY_ROOT = repo_root.display()
  } {
    sources.prepare_package_source_tree(work, work, isolated_pkg, source, false, false, false)?
  } ?

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
) [fs, error] -> Result[Unit] {
  pm_proof.verify_artifact_receipt(proof, node, payload)?
  let cached = execute_proof_cache_path(store_root, node.artifact_key, node.proof_key)
  fs.mkdir(cached.parent)?
  let lock = fs.lock(fp"${cached.parent}/${node.proof_key}.lock")?
  defer fs.unlock(lock)?

  if fs.exists(cached)? {
    pm_proof.verify_artifact_receipt(cached, node, payload)?
    return Ok()
  }

  let temporary = fp"${cached}.tmp"
  fs.remove(temporary, missing_ok: true)?
  defer fs.remove(temporary, missing_ok: true)?
  fs.copy(proof, temporary, overwrite: true)?
  fs.rename(temporary, cached)?
  pm_proof.verify_artifact_receipt(cached, node, payload)?
  return Ok()
}

proc execute_run_proof(
  node: types.PlanNode,
  pkg: types.Package,
  store_root: Path,
  payload: Path,
  proof: Path,
) [fs, process, env, error] -> Result[Unit] {
  if execute_cached_proof_is_valid(store_root, node, payload)? {
    return Ok()
  }

  # Metapackages select an already-proved dependency closure. They own neither
  # a payload archive nor a proof program, but still receive an immutable proof
  # receipt that binds this exact selector node to its opaque Store marker.
  if pkg.kind == types.package_meta() {
    pm_proof.write_artifact_receipt(proof, node, payload)?
    execute_publish_proof_cache(store_root, node, payload, proof)?
    return Ok()
  }

  let runtime_keys = [dependency.artifact_key for dependency in node.dependencies if dependency.kind == types.dependency_runtime()]
  let runtime_artifacts = execute_receipt_closure(store_root, runtime_keys)?
  let root_handle = fs.tempdir()?
  defer fs.close_root(root_handle)?
  let proof_root = execute_mutable_root(root_handle, "proof", runtime_artifacts, false)?
  # Payload archives contain their top-level directories (for example `usr`).
  # The proof root already has the executor substrate and runtime closure, so
  # extracting directly would reject that legitimate shared directory.  Extract
  # into a fresh path, then merge the verified tree with normal path-type
  # checks before the proof sees it.
  let payload_root = fp"${fs.root_path(root_handle)?}/proof-payload"
  archive.tar_extract(payload, payload_root, 0, "auto", true)?
  let _ = fs.copy_tree(payload_root, proof_root, parents: true, overwrite: true)?
  match pm_proof.run_artifact_proof(proof_root, pkg) {
    Ok(_) => {}
    Err(problem) => return Err(problem)
  }
  pm_proof.write_artifact_receipt(proof, node, payload)?
  execute_publish_proof_cache(store_root, node, payload, proof)?
  return Ok()
}

proc execute_build_local(
  plan_value: types.BuildPlan,
  node: types.PlanNode,
  repo_root: Path,
  store_root: Path,
) [fs, net, process, env, time, error] -> Result[types.ArtifactReceipt] {
  let pkg = execute_load_package(plan_value, node, repo_root)?
  let root_handle = fs.tempdir()?
  defer fs.close_root(root_handle)?
  let work = fs.root_path(root_handle)?
  var build_root = fp"${work}/meta-build-root"

  if pkg.kind == types.package_meta() {
    # Selectors have no build sandbox; their declared dependencies are ordered
    # by the BuildPlan and proved independently before this node executes.
    fs.mkdir(build_root)?
  } else {
    let dependency_keys = store.receipt_dependency_keys(node)
    let dependencies = execute_receipt_closure(store_root, dependency_keys)?
    build_root = execute_mutable_root(root_handle, "build", dependencies, true)?
  }

  let staged = execute_stage_local(plan_value, node, pkg, repo_root, build_root, work)?
  # Keep the proof outcome as Result data through this build-node boundary.
  # The published runner otherwise propagates a failing Unit proc directly out
  # of a par-map worker before its node-status marker can be written.
  match execute_run_proof(node, pkg, store_root, staged.payload, staged.proof) {
    Ok(_) => {}
    Err(problem) => return Err(problem)
  }
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

# Every node in a completed level must be a fully verified immutable receipt
# before its dependents may start. `par-map` keeps worker failures in-band
# unless the worker propagates them, so this boundary deliberately verifies
# both the returned receipt and the published store object by plan node order.
proc execute_verified_level(
  plan_value: types.BuildPlan,
  nodes: List[types.PlanNode],
  completed: List[types.ArtifactReceipt],
  store_root: Path,
) [fs, error] -> Result[List[types.ArtifactReceipt]] {
  if nodes.len() != completed.len() {
    return Err(types.PmError.PackageContract("executor level result count does not match its plan nodes"))
  }

  var receipts: List[types.ArtifactReceipt] = []
  var index = 0

  while index < nodes.len() {
    let node = nodes[index]
    let receipt = completed[index]
    execute_require_receipt(plan_value, node, receipt)?

    # `store.lookup` re-reads and hashes the renamed final directory. This
    # prevents a dependent level from observing merely a worker return value
    # rather than the receipt-last, atomic publication it requires.
    let published = store.lookup(store_root, node.artifact_key)?
    execute_require_receipt(plan_value, node, published)?
    receipts = receipts.push(published)
    index += 1
  }

  receipts
}

# The published runner erases `par-map`'s result element schema, including
# primitive `Str` values. Do not expose or type-bind that transient result.
# Each worker writes one unique transient outcome marker before its `?`
# propagation; after all workers stop, the parent converts that non-generic
# status back into the original node failure before it ever reads Store. This
# retains worker error propagation on runners that leave par-map errors
# in-band, while Store receipt-last publication remains the level boundary.
pure execute_parallel_level_ok_marker(status: Path, node: types.PlanNode) -> Path {
  fp"${status}/${node.artifact_key}.ok"
}

pure execute_parallel_level_error_marker(status: Path, node: types.PlanNode) -> Path {
  fp"${status}/${node.artifact_key}.error"
}

proc execute_parallel_level_worker(
  plan_value: types.BuildPlan,
  node: types.PlanNode,
  repo_root: Path,
  store_root: Path,
  remote_repo: Str,
  status: Path,
) [fs, net, process, env, time, error] -> Result[Unit] {
  # Keep the node Result as data until its failure marker is durable. The
  # caller reconstructs that marker after par-map completion; propagating it
  # here would make runner-specific erased par-map control flow observable.
  match build_node(plan_value, node, repo_root, store_root, remote_repo) {
    Ok(_) => {
      fs.write(execute_parallel_level_ok_marker(status, node), "ok\n")?
      return Ok()
    }
    Err(problem) => {
      fs.write(execute_parallel_level_error_marker(status, node), problem.message + "\n")?
      # The parent reconstructs and propagates this failure only after every
      # worker has joined. Returning success here avoids an erased par-map
      # result becoming a runner-dependent control-flow boundary.
      return Ok()
    }
  }
}

proc execute_parallel_level_require_workers(
  nodes: List[types.PlanNode],
  status: Path,
) [fs, error] {
  for node in nodes {
    let error_marker = execute_parallel_level_error_marker(status, node)

    if fs.exists(error_marker)? {
      let message = fs.read_text(error_marker)?.trim()
      return Err(types.PmError.ExtensionFailed(f"parallel executor node ${node.package_id} failed: ${message}"))
    }

    if !fs.exists(execute_parallel_level_ok_marker(status, node))? {
      return Err(types.PmError.PackageContract(f"parallel executor node ${node.package_id} did not report completion"))
    }
  }
}

# Once the ephemeral completion barrier succeeds, derive immutable keys from
# the known plan nodes and re-read receipt-last Store objects in ordinal order.
# This makes Store publication, rather than an erased parallel result, the
# executor's typed boundary.
proc execute_parallel_level(
  plan_value: types.BuildPlan,
  nodes: List[types.PlanNode],
  repo_root: Path,
  store_root: Path,
  remote_repo: Str,
  jobs: Int,
) [fs, net, process, env, time, error] -> Result[List[types.ArtifactReceipt]] {
  let handle = fs.tempdir()?
  defer fs.close_root(handle)?
  let status = fp"${fs.root_path(handle)?}/parallel-level-status"
  fs.mkdir(status)?

  let _ = nodes
    |> par-map --jobs=jobs { |node|
      execute_parallel_level_worker(plan_value, node, repo_root, store_root, remote_repo, status)?
      # The value is deliberately ignored: only its completion/error behavior
      # matters, and the published runner erases the par-map element schema.
      0
    }

  execute_parallel_level_require_workers(nodes, status)?

  var receipts: List[types.ArtifactReceipt] = []
  for node in nodes {
    let receipt = store.lookup(store_root, node.artifact_key)?
    execute_require_receipt(plan_value, node, receipt)?
    receipts = receipts.push(receipt)
  }
  return receipts
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

  # Keep action dispatch out of a constructor-pattern boundary.  The pinned
  # published runner parses qualified tag patterns differently from the newer
  # host checker; the typed predicate is stable across both runners.
  if types.plan_action_is_build(node.action) {
    return execute_build_local(plan_value, node, repo_root, store_root)
  }

  return execute_remote_node(plan_value, node, store_root, remote_repo)
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

    var completed: List[types.ArtifactReceipt] = []

    if jobs == 1 or level_nodes.len() == 1 {
      for node in level_nodes {
        completed = completed.push(build_node(plan_value, node, repo_root, store_root, remote_repo)?)
      }
    } else {
      # The postfix `?` is the scheduling boundary: without it par-map keeps
      # a failed worker in-band and a later level can attempt to consume that
      # worker's absent receipt. The verified-level barrier makes completion
      # of receipt-last publication explicit before advancing the plan.
      completed = execute_parallel_level(plan_value, level_nodes, repo_root, store_root, remote_repo, jobs)?
    }

    let verified = execute_verified_level(plan_value, level_nodes, completed, store_root)?

    for receipt in verified {
      artifacts = artifacts.push(receipt)
    }
  }

  # Keep the receipt list concrete at the public executor boundary. The
  # generated profile adapter crosses this boundary in a separate module and
  # must never receive an unparameterized List from the published runner.
  let result: types.BuildResult = {
    format: "laputa-build-result-1",
    plan_sha256: plan_value.plan_sha256,
    artifacts,
  }
  return result
}
