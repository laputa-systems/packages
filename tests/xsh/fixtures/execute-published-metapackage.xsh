##! Published-runner regression for metapackage execution without payload extraction or proof code.
use pm.catalog
use pm.execute
use pm.generation_adapter as generation_adapter
use pm.plan
use pm.plan_json
use pm.policy
use pm.proof as pm_proof
use pm.repo as pm_repo
use pm.store as artifact_store
use pm.types

proc write_dep_recipe(repo: Path) [fs, error] {
  let package = fp"${repo}/direct-dep"
  fs.mkdir(package)?
  fs.write(
    fp"${package}/PKGBUILD.xsh",
    r"""##! Published executor payload fixture.
## Package name.
export let name = "direct-dep"
## Package kind.
export let package_kind = "payload"
## Package version.
export let ver = "1.0.0"
## Package release.
export let rel = "1"
## Runtime dependencies.
export let deps = []
## Build-host dependencies.
export let mkdeps_host = []
## Build-target dependencies.
export let mkdeps_target = []
## Source declarations.
export let upstream_sources = []
## Payload inventory.
export let filetree = [{path: p"usr/share/direct-dep.txt", kind: "file"}]
## Package build operation.
export proc build(dest: Path) [fs, error] {
  let target = fp"${dest}/usr/share/direct-dep.txt"
  fs.mkdir(target.parent)?
  fs.write(target, "direct dependency\\n")?
}
""",
  )?
  fs.write(
    fp"${package}/proof.xsh",
    r"""error ProofError = Failed(message: Str)

proc main(root: Path) [fs, error] {
  if ! fs.exists(fp"${root}/var/lib/xsh-pm/packages/direct-dep/metadata.json")? {
    return Err(ProofError.Failed("dependency proof did not receive package metadata"))
  }
}

main(@args)?
""",
  )?
}

proc write_meta_recipe(repo: Path) [fs, error] {
  let package = fp"${repo}/direct-meta"
  fs.mkdir(package)?
  fs.write(
    fp"${package}/PKGBUILD.xsh",
    r"""##! Published executor metapackage fixture without a proof script.
## Package name.
export let name = "direct-meta"
## Package kind.
export let package_kind = "meta"
## Package version.
export let ver = "1.0.0"
## Package release.
export let rel = "1"
## Runtime dependencies.
export let deps = ["direct-dep"]
## Build-host dependencies.
export let mkdeps_host = []
## Build-target dependencies.
export let mkdeps_target = []
## Source declarations.
export let upstream_sources = []
## Metapackage inventory.
export let filetree = []
""",
  )?
}

proc write_level_barrier_recipes(repo: Path) [fs, error] {
  let tool = fp"${repo}/direct-tool"
  fs.mkdir(tool)?
  fs.write(
    fp"${tool}/PKGBUILD.xsh",
    r"""##! Independent executor tool fixture for the parallel-level barrier.
## Package name.
export let name = "direct-tool"
## Package kind.
export let package_kind = "payload"
## Package version.
export let ver = "1.0.0"
## Package release.
export let rel = "1"
## Runtime dependencies.
export let deps = []
## Build-host dependencies.
export let mkdeps_host = []
## Build-target dependencies.
export let mkdeps_target = []
## Source declarations.
export let upstream_sources = []
## Payload inventory.
export let filetree = [{path: p"usr/share/direct-tool.txt", kind: "file"}]
## Package build operation.
export proc build(dest: Path) [fs, error] {
  let target = fp"${dest}/usr/share/direct-tool.txt"
  fs.mkdir(target.parent)?
  fs.write(target, "direct tool\n")?
}
""",
  )?
  fs.write(
    fp"${tool}/proof.xsh",
    r"""proc main(root: Path) [error] {}

main(@args)?
""",
  )?

  let app = fp"${repo}/direct-app"
  fs.mkdir(app)?
  fs.write(
    fp"${app}/PKGBUILD.xsh",
    r"""##! Level-one executor fixture that fails only after its payload is staged.
## Package name.
export let name = "direct-app"
## Package kind.
export let package_kind = "payload"
## Package version.
export let ver = "1.0.0"
## Package release.
export let rel = "1"
## Runtime dependencies.
export let deps = ["direct-dep"]
## Build-host dependencies.
export let mkdeps_host = ["direct-tool"]
## Build-target dependencies.
export let mkdeps_target = []
## Source declarations.
export let upstream_sources = []
## Payload inventory.
export let filetree = [{path: p"usr/share/direct-app.txt", kind: "file"}]
## Package build operation.
export proc build(dest: Path) [fs, env, error] {
  let root = env("LAPUTA_ROOT")?
  let _ = fs.read_text(fp"${root}/usr/share/direct-dep.txt")?
  let _ = fs.read_text(fp"${root}/usr/share/direct-tool.txt")?
  let target = fp"${dest}/usr/share/direct-app.txt"
  fs.mkdir(target.parent)?
  fs.write(target, "direct app\n")?
}
""",
  )?
  fs.write(
    fp"${app}/proof.xsh",
    r"""error ProofError = Failed(message: Str)

proc main(root: Path) [error] {
  return Err(ProofError.Failed("intentional published level-one proof failure"))
}

main(@args)?
""",
  )?

  # A successful peer forces direct-app's proof failure through the actual
  # multi-node par-map bridge rather than the executor's sequential fast path.
  let peer = fp"${repo}/direct-peer"
  fs.mkdir(peer)?
  fs.write(
    fp"${peer}/PKGBUILD.xsh",
    r"""##! Parallel peer fixture for the executor failure barrier.
## Package name.
export let name = "direct-peer"
## Package kind.
export let package_kind = "payload"
## Package version.
export let ver = "1.0.0"
## Package release.
export let rel = "1"
## Runtime dependencies.
export let deps = ["direct-dep"]
## Build-host dependencies.
export let mkdeps_host = []
## Build-target dependencies.
export let mkdeps_target = []
## Source declarations.
export let upstream_sources = []
## Payload inventory.
export let filetree = [{path: p"usr/share/direct-peer.txt", kind: "file"}]
## Package build operation.
export proc build(dest: Path) [fs, env, error] {
  let root = env("LAPUTA_ROOT")?
  let _ = fs.read_text(fp"${root}/usr/share/direct-dep.txt")?
  let target = fp"${dest}/usr/share/direct-peer.txt"
  fs.mkdir(target.parent)?
  fs.write(target, "direct peer\n")?
}
""",
  )?
  fs.write(
    fp"${peer}/proof.xsh",
    r"""proc main(root: Path) [error] {}

main(@args)?
""",
  )?

  let leaf = fp"${repo}/direct-leaf"
  fs.mkdir(leaf)?
  fs.write(
    fp"${leaf}/PKGBUILD.xsh",
    r"""##! Level-two executor fixture that must not start after a failed level one.
## Package name.
export let name = "direct-leaf"
## Package kind.
export let package_kind = "payload"
## Package version.
export let ver = "1.0.0"
## Package release.
export let rel = "1"
## Runtime dependencies.
export let deps = ["direct-app", "direct-peer"]
## Build-host dependencies.
export let mkdeps_host = []
## Build-target dependencies.
export let mkdeps_target = []
## Source declarations.
export let upstream_sources = []
## Payload inventory.
export let filetree = [{path: p"usr/share/direct-leaf.txt", kind: "file"}]
## Package build operation.
export proc build(dest: Path) [fs, env, error] {
  let root = env("LAPUTA_ROOT")?
  let _ = fs.read_text(fp"${root}/usr/share/direct-app.txt")?
  let target = fp"${dest}/usr/share/direct-leaf.txt"
  fs.mkdir(target.parent)?
  fs.write(target, "direct leaf\n")?
}
""",
  )?
  fs.write(
    fp"${leaf}/proof.xsh",
    r"""proc main(root: Path) [error] {}

main(@args)?
""",
  )?
}

proc published_parallel_level_barrier_regression(
  workspace: Path,
  executor: types.ExecutorIdentity,
) [fs, net, process, env, time, error] {
  let repo = fp"${workspace}/repo"
  let store = fp"${workspace}/level-barrier-store"
  write_level_barrier_recipes(repo)?
  let value = plan.resolve(
    catalog.load(workspace)?,
    {target: types.target_aarch64(), index_sha256: "", packages: []},
    policy.aarch64_docker(),
    ["direct-leaf"],
    false,
    executor,
  )?
  let app = value.nodes[2]
  let peer = value.nodes[3]
  let leaf = value.nodes[4]

  if app.name != "direct-app" or app.level != 1 or peer.name != "direct-peer" or peer.level != 1 or leaf.name != "direct-leaf" or leaf.level != 2 or leaf.dependencies[0].artifact_key != app.artifact_key {
    return error.fail("published level-barrier fixture did not resolve exact dependency levels")
  }

  match execute.build_plan(value, workspace, store, "", 2) {
    Ok(_) => return error.fail("published executor advanced past a failed dependency level")
    Err(problem) => {
      # The published runner leaves a failed par-map callback in-band. The
      # executor must report the worker's node-specific marker before it
      # attempts Store lookup or allows a later level to consume direct-app.
      if !problem.message.contains("parallel executor node direct-app-1.0.0-1 failed: package proof for direct-app") {
        return Err(problem)
      }
    }
  }

  if !fs.exists(artifact_store.artifact_path(store, peer.artifact_key))? {
    return error.fail("published executor did not wait for the successful parallel peer")
  }

  if fs.exists(artifact_store.artifact_path(store, app.artifact_key))? or fs.exists(artifact_store.artifact_path(store, leaf.artifact_key))? {
    return error.fail("published executor materialized a failed-level artifact or its dependent")
  }
}

proc published_legacy_package_kind_regression(
  value: types.BuildPlan,
  workspace: Path,
) [fs, error] {
  let node = value.nodes[0]
  let stage = fp"${workspace}/legacy-stage"
  let legacy_store = fp"${workspace}/legacy-store"
  let payload = fp"${stage}/payload.tar.gz"
  let metadata = fp"${stage}/metadata.json"
  let proof = fp"${stage}/proof.json"
  fs.mkdir(stage)?
  fs.write(payload, "published legacy payload\n")?
  # The only legacy exception is an omitted package_kind.  The store receipt
  # binds these exact bytes before repo publication decodes them.
  json.write(metadata, {arch: "aarch64", name: node.name, ver: node.ver, rel: node.rel, files: []})?
  pm_proof.write_artifact_receipt(proof, node, payload)?
  let executor_sha256 = plan.executor_fingerprint(value.executor)?
  let _ = artifact_store.commit(legacy_store, node, {payload, metadata, proof, executor_sha256})?
  let snapshot = pm_repo.snapshot(value, legacy_store)?

  if snapshot.packages[0].kind != types.package_payload() {
    return error.fail("published omitted package_kind did not default to payload")
  }

  let invalid_stage = fp"${workspace}/invalid-stage"
  let invalid_store = fp"${workspace}/invalid-store"
  let invalid_payload = fp"${invalid_stage}/payload.tar.gz"
  let invalid_metadata = fp"${invalid_stage}/metadata.json"
  let invalid_proof = fp"${invalid_stage}/proof.json"
  fs.mkdir(invalid_stage)?
  fs.write(invalid_payload, "published invalid payload\n")?
  json.write(invalid_metadata, {arch: "aarch64", name: node.name, ver: node.ver, rel: node.rel, package_kind: "", files: []})?
  pm_proof.write_artifact_receipt(invalid_proof, node, invalid_payload)?
  let _ = artifact_store.commit(invalid_store, node, {payload: invalid_payload, metadata: invalid_metadata, proof: invalid_proof, executor_sha256})?

  match pm_repo.snapshot(value, invalid_store) {
    Ok(_) => return error.fail("published explicit empty package_kind unexpectedly published")
    Err(problem) => {
      if !problem.message.contains("invalid package kind") {
        return Err(problem)
      }
    }
  }
}

# Exercise the exact external-process boundary used by Laputa's native image
# adapter. The first level has two successful independent nodes, so the
# published runner must wait for generic-free `par-map` completion, then
# reconstruct typed receipts from the immutable Store before crossing
# `BuildResult` and `generation_adapter_execute_profile`.
proc published_generation_adapter_regression(
  workspace: Path,
  executor: types.ExecutorIdentity,
) [fs, net, process, env, time, error] {
  let repo = fp"${workspace}/repo"
  let plan_path = fp"${workspace}/adapter-build-plan.json"
  let store = fp"${workspace}/adapter-store"
  let overlay = fp"${workspace}/adapter-overlay"
  let output_parent = fp"${workspace}/adapter-generations"
  let generation_plan = fp"${workspace}/adapter-generation-plan.json"
  let generation_receipt = fp"${workspace}/adapter-generation.json"
  write_level_barrier_recipes(repo)?
  fs.mkdir(overlay)?

  let value = plan.resolve(
    catalog.load(workspace)?,
    {target: types.target_aarch64(), index_sha256: "", packages: []},
    policy.aarch64_docker(),
    ["direct-meta", "direct-tool"],
    false,
    executor,
  )?
  plan_json.write_plan(plan_path, value)?
  let result = generation_adapter.generation_adapter_execute_profile(
    plan_path,
    workspace,
    store,
    2,
    ["direct-meta", "direct-tool"],
    "default",
    overlay,
    output_parent,
    generation_plan,
    generation_receipt,
    [],
  )?

  if !fs.exists(result.generation_root)? or !fs.exists(generation_plan)? or !fs.exists(generation_receipt)? {
    return error.fail("published generation adapter did not compose its verified generation")
  }
}

proc main() [fs, net, process, env, time, error] {
  let workspace = p"/tmp/laputa-published-metapackage"
  fs.remove(workspace, missing_ok: true)?
  defer fs.remove(workspace, missing_ok: true)?
  let repo = fp"${workspace}/repo"
  let store = fp"${workspace}/store"
  fs.mkdir(repo)?
  fs.mkdir(fp"${workspace}/pm")?
  # The fixture runs from the mounted package checkout.  Keep its copied proof
  # helper repository-relative so the published runner does not depend on a
  # particular mount prefix.
  fs.copy(p"pm/proof.xsh", fp"${workspace}/pm/proof.xsh", overwrite: true)?
  write_dep_recipe(repo)?
  write_meta_recipe(repo)?
  let executor: types.ExecutorIdentity = {
    format: "laputa-pm-executor-1",
    pm_sha256: "published-pm",
    xsh_sha256: "published-xsh",
    core_sha256: "published-core",
  }
  let catalog_value = catalog.load(workspace)?
  let value = plan.resolve(
    catalog_value,
    {target: types.target_aarch64(), index_sha256: "", packages: []},
    policy.aarch64_docker(),
    ["direct-meta"],
    false,
    executor,
  )?
  let legacy_value = plan.resolve(
    catalog_value,
    {target: types.target_aarch64(), index_sha256: "", packages: []},
    policy.aarch64_docker(),
    ["direct-dep"],
    false,
    executor,
  )?
  let result = execute.build_plan(value, workspace, store, "", 1)?
  let meta = result.artifacts[1]
  let metadata: Record = json.read(fp"${meta.artifact_dir}/metadata.json")?
  let files = metadata.get("files")?.require(List[Record])?

  if meta.package_name != "direct-meta" or metadata.get("package_kind")? != "meta" or files.len() != 0 {
    return error.fail("published metapackage did not retain an empty typed payload inventory")
  }

  if fs.read_text(fp"${meta.artifact_dir}/payload.tar.gz")? != "laputa metapackage payload marker\n" {
    return error.fail("published metapackage payload marker changed or was extracted")
  }

  if ! fs.exists(fp"${result.artifacts[0].artifact_dir}/proof.json")? or ! fs.exists(fp"${meta.artifact_dir}/proof.json")? {
    return error.fail("published metapackage execution did not retain dependency and selector proof receipts")
  }

  published_parallel_level_barrier_regression(workspace, executor)?
  published_legacy_package_kind_regression(legacy_value, workspace)?
  published_generation_adapter_regression(workspace, executor)?

  print "execute-published-metapackage-ok"
}

main()?
