##! Publication of completed immutable BuildPlan artifacts.
use plan as build_plan
use proof as pm_proof
use remote
use store
use types
use util

# Artifact metadata gained `package_kind` after the legacy repository format.
# Keep the required tuple typed, then accept only that one omitted legacy field
# at this boundary.  New metadata must name an explicit valid kind.
type RepoArtifactMetadataDto = {name: Str, ver: Str, rel: Str}
type RepoIndexMerge = {index: List[types.RemotePackage], already_published: Bool}
type RepoPublishStage = {publication: types.RepoPublication, entry: types.RemotePackage, metadata: Path}

proc repo_expected_executor_sha256(value: types.BuildPlan) [error] -> Result[Str] {
  build_plan.executor_fingerprint(value.executor)?
}

proc repo_verify_node_receipt(
  value: types.BuildPlan,
  node: types.PlanNode,
  receipt: types.ArtifactReceipt,
) [error] {
  let executor_sha256 = repo_expected_executor_sha256(value)?
  let dependency_keys = store.receipt_dependency_keys(node)
  let runtime_dependency_keys = store.receipt_runtime_dependency_keys(node)

  if receipt.key != node.artifact_key or receipt.target != value.target or receipt.package_name != node.name or receipt.package_id != node.package_id or receipt.recipe_sha256 != node.recipe_sha256 or receipt.dependency_keys != dependency_keys or receipt.runtime_dependency_keys != runtime_dependency_keys {
    return Err(types.PmError.PackageContract(f"artifact receipt ${node.artifact_key} does not match BuildPlan node ${node.package_id}"))
  }

  if ! build_plan.node_uses_legacy_remote_identity(value, node)? and receipt.executor_sha256 != executor_sha256 {
    return Err(types.PmError.PackageContract(f"artifact receipt ${node.artifact_key} executor does not match BuildPlan node ${node.package_id}"))
  }

  if types.plan_action_is_build(node.action) {
    if receipt.origin != types.artifact_origin_built() {
      return Err(types.PmError.PackageContract(f"BuildPlan build node ${node.package_id} is not a locally proved artifact"))
    }
  } else if receipt.origin != types.artifact_origin_remote() {
    return Err(types.PmError.PackageContract(f"BuildPlan remote node ${node.package_id} is not a verified imported artifact"))
  }
}

proc repo_package_kind(receipt: types.ArtifactReceipt, node: types.PlanNode) [fs, error] -> Result[types.PackageKind] {
  let metadata = fp"${receipt.artifact_dir}/metadata.json"
  let raw: Record = json.read(metadata)?
  let core = raw.require(RepoArtifactMetadataDto)?

  if core.name != node.name or core.ver != node.ver or core.rel != node.rel {
    return Err(types.PmError.PackageContract(f"artifact metadata ${metadata.display()} does not match ${node.package_id}"))
  }

  if raw.has("package_kind") {
    return types.parse_package_kind(raw.get("package_kind")?.require(Str)?)
  }

  # Package-kind fields appeared after legacy remote metadata. Its omitted form was payload.
  types.package_payload()
}

proc repo_verified_proof_path(
  store_root: Path,
  node: types.PlanNode,
  receipt: types.ArtifactReceipt,
) [fs, error] -> Result[Path] {
  let payload = fp"${receipt.artifact_dir}/payload.tar.gz"
  let primary = fp"${receipt.artifact_dir}/proof.json"

  if receipt.origin == types.artifact_origin_remote() {
    # import_remote hashes and verifies its opaque remote proof object through the Store receipt.
    return primary
  }

  if receipt.proof_key == node.proof_key {
    pm_proof.verify_artifact_receipt(primary, node, payload)?
    return primary
  }

  let reproved = fp"${store_root}/v1/proofs/${node.artifact_key}/${node.proof_key}.json"

  if ! fs.exists(reproved)? {
    return Err(types.PmError.PackageTarball(f"${node.package_id} is missing proof ${node.proof_key}; execute the BuildPlan before publication"))
  }

  pm_proof.verify_artifact_receipt(reproved, node, payload)?
  reproved
}

## Selects every BuildPlan node from verified immutable Store receipts without building or resolving a remote index.
export proc snapshot(value: types.BuildPlan, store_root: Path) [fs, error] -> Result[types.RepoSnapshot] {
  build_plan.validate(value)?
  var packages: List[types.RepoPublication] = []

  for node in value.nodes {
    let receipt = store.lookup(store_root, node.artifact_key)?
    repo_verify_node_receipt(value, node, receipt)?
    let kind = repo_package_kind(receipt, node)?
    let proof = repo_verified_proof_path(store_root, node, receipt)?
    packages = packages.push({
      node,
      receipt,
      payload: fp"${receipt.artifact_dir}/payload.tar.gz",
      metadata: fp"${receipt.artifact_dir}/metadata.json",
      proof,
      kind,
    })
  }

  {format: "laputa-repo-snapshot-1", target: value.target, plan_sha256: value.plan_sha256, packages}
}

proc repo_metadata_for_publication(value: types.RepoPublication, output: Path) [fs, error] -> Result[Path] {
  let raw: Record = json.read(value.metadata)?
  let metadata = fp"${output}/${value.node.artifact_key}.json"
  fs.mkdir(metadata.parent)?
  fs.write_atomic(
    metadata,
    json.encode({
      ...raw,
      arch: "aarch64",
      target: types.target_text(value.receipt.target),
      artifact_key: value.node.artifact_key,
      recipe_sha256: value.node.recipe_sha256,
      executor_sha256: value.receipt.executor_sha256,
      proof_key: value.node.proof_key,
      proof_sha256: value.node.proof_sha256,
    })? + "\n",
  )?
  metadata
}

proc repo_publication_entry(value: types.RepoPublication, metadata: Path) [fs, error] -> Result[types.RemotePackage] {
  let node = value.node
  let payload_rel = util.remote_binary_rel("aarch64", node.name, node.ver, node.rel)
  let metadata_rel = util.remote_metadata_rel("aarch64", node.name, node.ver, node.rel)
  let proof_rel = util.remote_proof_rel("aarch64", node.name, node.ver, node.rel)
  let metadata_sha256 = hash.sha256(metadata)?.hex()
  let proof_receipt_sha256 = hash.sha256(value.proof)?.hex()

  {
    arch: "aarch64",
    name: node.name,
    ver: node.ver,
    rel: node.rel,
    deps: [dependency.name for dependency in node.dependencies if dependency.kind == types.dependency_runtime()],
    mkdeps_host: [dependency.name for dependency in node.dependencies if dependency.kind == types.dependency_build_host()],
    mkdeps_target: [dependency.name for dependency in node.dependencies if dependency.kind == types.dependency_build_target()],
    sha256: if value.kind == types.package_meta() { "" } else { hash.sha256(value.payload)?.hex() },
    size: if value.kind == types.package_meta() { 0 } else { fs.metadata(value.payload)?.size },
    tarball: if value.kind == types.package_meta() { "" } else { payload_rel.display() },
    metadata: metadata_rel.display(),
    metadata_sha256,
    artifact_key: node.artifact_key,
    recipe_sha256: node.recipe_sha256,
    executor_sha256: value.receipt.executor_sha256,
    proof_key: node.proof_key,
    proof_sha256: node.proof_sha256,
    proof: proof_rel.display(),
    proof_receipt_sha256,
    source_sha256: "",
    metapackage: value.kind == types.package_meta(),
  }
}

proc repo_same_publication(left: types.RemotePackage, right: types.RemotePackage) [] -> Bool {
  left.arch == right.arch and left.name == right.name and left.ver == right.ver and left.rel == right.rel and left.deps == right.deps and left.mkdeps_host == right.mkdeps_host and left.mkdeps_target == right.mkdeps_target and left.sha256 == right.sha256 and left.size == right.size and left.tarball == right.tarball and left.metadata == right.metadata and left.metadata_sha256 == right.metadata_sha256 and left.artifact_key == right.artifact_key and left.recipe_sha256 == right.recipe_sha256 and left.executor_sha256 == right.executor_sha256 and left.proof_key == right.proof_key and left.proof_sha256 == right.proof_sha256 and left.proof == right.proof and left.proof_receipt_sha256 == right.proof_receipt_sha256 and left.source_sha256 == right.source_sha256 and left.metapackage == right.metapackage
}

proc repo_merge_publication(index: List[types.RemotePackage], entry: types.RemotePackage) [error] -> Result[RepoIndexMerge] {
  var updated: List[types.RemotePackage] = []
  var replaced = false

  for existing in index {
    if existing.arch == entry.arch and existing.name == entry.name {
      if existing.ver == entry.ver and existing.rel == entry.rel {
        if ! repo_same_publication(existing, entry) {
          return Err(types.PmError.PackageConflict(f"immutable remote tuple ${entry.arch}/${entry.name}-${entry.ver}-${entry.rel} already exists with different content"))
        }

        return {index, already_published: true}
      }

      updated = updated.push(entry)
      replaced = true
    } else {
      updated = updated.push(existing)
    }
  }

  if ! replaced {
    updated = updated.push(entry)
  }

  {index: updated |> sort-by { |item| f"${item.arch}\t${item.name}" }, already_published: false}
}

proc repo_publish_immutable_object(repo_url: Str, rel: Path, source: Path, token: Str, work: Path) [fs, net, error] {
  let _ = remote.upload_immutable_repo_file(repo_url, rel, source, token, work)?
}

## Publishes a verified repository snapshot: immutable package objects first and the remote index last.
export proc publish(snapshot: types.RepoSnapshot, remote_repo: Str, token: Str, work: Path) [fs, net, time, error] {
  if snapshot.format != "laputa-repo-snapshot-1" or snapshot.target != types.target_aarch64() {
    return Err(types.PmError.PackageContract("unsupported repository snapshot"))
  }

  if remote_repo == "" {
    return Err(types.PmError.RemoteRepo("repository publication needs a remote repository"))
  }

  if ! util.is_file_url(remote_repo) and token.trim() == "" {
    return Err(types.PmError.Auth("repository publication needs LAPUTA_TOKEN for network remotes"))
  }

  fs.mkdir(work)?
  var stages: List[RepoPublishStage] = []

  for publication in snapshot.packages {
    let verified = store.verify_receipt(publication.receipt)?

    if verified != publication.receipt {
      return Err(types.PmError.PackageContract(f"repository snapshot receipt changed for ${publication.node.package_id}"))
    }

    if publication.receipt.origin == types.artifact_origin_built() {
      pm_proof.verify_artifact_receipt(publication.proof, publication.node, publication.payload)?
    }

    let metadata = repo_metadata_for_publication(publication, fp"${work}/metadata")?
    stages = stages.push({publication, entry: repo_publication_entry(publication, metadata)?, metadata})
  }

  # This is the sole remote-index read. It establishes immutable tuple conflicts before any object upload.
  var index = remote.load_remote_index_from_repo(remote_repo, fp"${work}/index")?
  var pending: List[RepoPublishStage] = []

  for stage in stages {
    let merged = repo_merge_publication(index, stage.entry)?
    index = merged.index

    if merged.already_published {
      print ${stage.entry.arch} ${stage.entry.name} util.version_id(stage.entry.ver, stage.entry.rel) "already-published"
    } else {
      pending = pending.push(stage)
    }
  }

  for stage in pending {
    if ! stage.entry.metapackage {
      repo_publish_immutable_object(remote_repo, fp"${stage.entry.tarball}", stage.publication.payload, token, work)?
    }

    repo_publish_immutable_object(remote_repo, fp"${stage.entry.metadata}", stage.metadata, token, work)?
    repo_publish_immutable_object(remote_repo, fp"${stage.entry.proof}", stage.publication.proof, token, work)?
  }

  if pending.len() > 0 {
    remote.write_remote_index_to_repo(remote_repo, work, fp"${work}/index", index, token)?
  }
}
