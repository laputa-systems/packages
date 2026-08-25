##! Immutable, content-verified package artifacts addressed by semantic SHA-256 keys; finals appear only after a verified temporary-directory rename, and XSH reserves standard `path`, so exports use `artifact_path`.
use remote
use types
use util

type ArtifactReceiptDto = {
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

type RemoteMetadataDto = {name: Str, ver: Str, rel: Str}

pure store_v1(root: Path) -> Path {
  fp"${root}/v1"
}

pure object_root(root: Path) -> Path {
  fp"${store_v1(root)}/sha256"
}

pure lock_path(root: Path, key: Str) -> Path {
  fp"${store_v1(root)}/locks/${key}.lock"
}

pure temporary_path(root: Path, key: Str) -> Path {
  fp"${store_v1(root)}/tmp/${key}"
}

pure receipt_path(dir: Path) -> Path {
  fp"${dir}/artifact.json"
}

pure payload_path(dir: Path) -> Path {
  fp"${dir}/payload.tar.gz"
}

pure metadata_path(dir: Path) -> Path {
  fp"${dir}/metadata.json"
}

pure proof_path(dir: Path) -> Path {
  fp"${dir}/proof.json"
}

pure sha256_text_is_valid(value: Str) -> Bool {
  value.count_chars() == 64 and value == value.lower() and value.delete("0123456789abcdef") == ""
}

proc require_sha256(value: Str, label: Str) [error] {
  if ! sha256_text_is_valid(value) {
    return Err(types.PmError.PackageContract(f"${label} must be a lowercase SHA-256 digest"))
  }
}

proc require_key(key: Str) [error] {
  require_sha256(key, "artifact key")?
}

pure receipt_dto(value: types.ArtifactReceipt) -> ArtifactReceiptDto {
  {
    format: value.format,
    key: value.key,
    target: types.target_text(value.target),
    package_name: value.package_name,
    package_id: value.package_id,
    origin: types.artifact_origin_text(value.origin),
    recipe_sha256: value.recipe_sha256,
    executor_sha256: value.executor_sha256,
    payload_sha256: value.payload_sha256,
    metadata_sha256: value.metadata_sha256,
    proof_key: value.proof_key,
    proof_sha256: value.proof_sha256,
    dependency_keys: value.dependency_keys,
    runtime_dependency_keys: value.runtime_dependency_keys,
  }
}

proc receipt_from_dto(value: ArtifactReceiptDto, artifact_dir: Path) [error] -> Result[types.ArtifactReceipt] {
  {
    format: value.format,
    key: value.key,
    target: types.parse_target(value.target)?,
    package_name: value.package_name,
    package_id: value.package_id,
    origin: types.parse_artifact_origin(value.origin)?,
    recipe_sha256: value.recipe_sha256,
    executor_sha256: value.executor_sha256,
    payload_sha256: value.payload_sha256,
    metadata_sha256: value.metadata_sha256,
    proof_key: value.proof_key,
    proof_sha256: value.proof_sha256,
    dependency_keys: value.dependency_keys,
    runtime_dependency_keys: value.runtime_dependency_keys,
    artifact_dir,
  }
}

proc validate_receipt(value: types.ArtifactReceipt, expected_key: Str) [error] {
  if value.format != "laputa-package-artifact-1" {
    return Err(types.PmError.PackageContract(f"unsupported artifact receipt format ${value.format}"))
  }

  require_key(expected_key)?
  require_key(value.key)?

  if value.key != expected_key {
    return Err(types.PmError.PackageContract(f"artifact receipt key ${value.key} does not match ${expected_key}"))
  }

  if value.target != types.Aarch64LinuxMusl {
    return Err(types.PmError.PackageContract("artifact receipt must target aarch64-linux-musl"))
  }

  if value.package_name == "" or value.package_name.contains("\n") {
    return Err(types.PmError.PackageContract("artifact receipt package_name is invalid"))
  }

  if value.package_id == "" or value.package_id.contains("\n") {
    return Err(types.PmError.PackageContract("artifact receipt package_id is invalid"))
  }

  require_sha256(value.recipe_sha256, "artifact receipt recipe_sha256")?
  require_sha256(value.executor_sha256, "artifact receipt executor_sha256")?
  require_sha256(value.payload_sha256, "artifact receipt payload_sha256")?
  require_sha256(value.metadata_sha256, "artifact receipt metadata_sha256")?
  require_sha256(value.proof_key, "artifact receipt proof_key")?
  require_sha256(value.proof_sha256, "artifact receipt proof_sha256")?

  var seen: Map[Bool] = {}

  for dependency_key in value.dependency_keys {
    require_sha256(dependency_key, "artifact receipt dependency key")?

    if seen.has(dependency_key) {
      return Err(types.PmError.PackageContract(f"artifact receipt repeats dependency key ${dependency_key}"))
    }

    seen[dependency_key] = true
  }

  var seen_runtime: Map[Bool] = {}

  for dependency_key in value.runtime_dependency_keys {
    require_sha256(dependency_key, "artifact receipt runtime dependency key")?

    if ! seen.has(dependency_key) {
      return Err(types.PmError.PackageContract(f"artifact receipt runtime dependency key ${dependency_key} is not a dependency"))
    }

    if seen_runtime.has(dependency_key) {
      return Err(types.PmError.PackageContract(f"artifact receipt repeats runtime dependency key ${dependency_key}"))
    }

    seen_runtime[dependency_key] = true
  }
}

proc read_receipt(dir: Path, expected_key: Str) [fs, error] -> Result[types.ArtifactReceipt] {
  let dto = json.read(receipt_path(dir))?.require(ArtifactReceiptDto)?
  let value = receipt_from_dto(dto, dir)?
  validate_receipt(value, expected_key)?
  value
}

proc verify_dir(dir: Path, expected_key: Str) [fs, error] -> Result[types.ArtifactReceipt] {
  let value = read_receipt(dir, expected_key)?
  let payload = payload_path(dir)
  let metadata = metadata_path(dir)
  let proof = proof_path(dir)

  if ! fs.exists(payload)? or ! fs.exists(metadata)? or ! fs.exists(proof)? {
    return Err(types.PmError.PackageContract(f"artifact ${expected_key} is incomplete"))
  }

  let actual_payload = hash.sha256(payload)?.hex()

  if actual_payload != value.payload_sha256 {
    return Err(types.PmError.PackageContract(f"artifact ${expected_key} payload SHA-256 does not match receipt"))
  }

  let actual_metadata = hash.sha256(metadata)?.hex()

  if actual_metadata != value.metadata_sha256 {
    return Err(types.PmError.PackageContract(f"artifact ${expected_key} metadata SHA-256 does not match receipt"))
  }

  let actual_proof = hash.sha256(proof)?.hex()

  if actual_proof != value.proof_sha256 {
    return Err(types.PmError.PackageContract(f"artifact ${expected_key} proof SHA-256 does not match receipt"))
  }

  value
}

proc receipt_for(
  node: types.PlanNode,
  dir: Path,
  executor_sha256: Str,
  origin: types.ArtifactOrigin,
) [fs, error] -> Result[types.ArtifactReceipt] {
  require_key(node.artifact_key)?
  require_sha256(node.recipe_sha256, "plan node recipe_sha256")?
  require_sha256(node.proof_key, "plan node proof_key")?
  require_sha256(executor_sha256, "staged executor_sha256")?

  let payload = payload_path(dir)
  let metadata = metadata_path(dir)
  let proof = proof_path(dir)

  if ! fs.exists(payload)? or ! fs.exists(metadata)? or ! fs.exists(proof)? {
    return Err(types.PmError.PackageContract(f"staged artifact for ${node.package_id} is incomplete"))
  }

  {
    format: "laputa-package-artifact-1",
    key: node.artifact_key,
    target: types.Aarch64LinuxMusl,
    package_name: node.name,
    package_id: node.package_id,
    origin,
    recipe_sha256: node.recipe_sha256,
    executor_sha256,
    payload_sha256: hash.sha256(payload)?.hex(),
    metadata_sha256: hash.sha256(metadata)?.hex(),
    proof_key: node.proof_key,
    proof_sha256: hash.sha256(proof)?.hex(),
    dependency_keys: [dependency.artifact_key for dependency in node.dependencies],
    runtime_dependency_keys: [dependency.artifact_key for dependency in node.dependencies if dependency.kind == types.Runtime],
    artifact_dir: dir,
  }
}

proc write_receipt(dir: Path, value: types.ArtifactReceipt) [fs, error] {
  fs.write(receipt_path(dir), json.encode(receipt_dto(value))? + "\n")?
}

proc copy_staged(dir: Path, staged: types.StagedArtifact) [fs, error] {
  fs.copy(staged.payload, payload_path(dir))?
  fs.copy(staged.metadata, metadata_path(dir))?
  fs.copy(staged.proof, proof_path(dir))?
}

proc commit_locked(
  root: Path,
  node: types.PlanNode,
  staged: types.StagedArtifact,
  origin: types.ArtifactOrigin,
) [fs, error] -> Result[types.ArtifactReceipt] {
  let key = node.artifact_key
  let final_dir = artifact_path(root, key)

  if fs.exists(final_dir)? {
    return verify_artifact(root, key)
  }

  let temporary = temporary_path(root, key)
  fs.remove(temporary, missing_ok: true)?
  defer fs.remove(temporary, missing_ok: true)?
  fs.mkdir(temporary)?
  copy_staged(temporary, staged)?
  let value = receipt_for(node, temporary, staged.executor_sha256, origin)?

  # artifact.json is intentionally the final temporary write: a directory with it is complete only after verification.
  write_receipt(temporary, value)?
  let _ = verify_dir(temporary, key)?
  fs.mkdir(final_dir.parent)?
  fs.rename(temporary, final_dir)?
  verify_artifact(root, key)
}

proc commit_staged(
  root: Path,
  node: types.PlanNode,
  staged: types.StagedArtifact,
  origin: types.ArtifactOrigin,
) [fs, error] -> Result[types.ArtifactReceipt] {
  let key = node.artifact_key
  require_key(key)?
  let lock_file = lock_path(root, key)
  fs.mkdir(lock_file.parent)?
  let lock = fs.lock(lock_file)?
  defer fs.unlock(lock)?
  commit_locked(root, node, staged, origin)?
}

proc fetch_remote_object(
  remote_repo: Str,
  rel: Path,
  cache_path: Path,
  expected_sha256: Str,
  label: Str,
) [fs, net, error] {
  require_sha256(expected_sha256, f"remote ${label} SHA-256")?
  let failure = remote.try_fetch_repo_file(remote_repo, util.ensure_relative_path(rel, f"remote ${label}")?, cache_path)?

  if failure != "" {
    return Err(types.PmError.RemoteFetch(failure))
  }

  let actual = hash.sha256(cache_path)?.hex()

  if actual != expected_sha256 {
    fs.remove(cache_path, missing_ok: true)?
    return Err(types.PmError.RemoteFetch(f"remote ${label} SHA-256 mismatch: expected ${expected_sha256}, got ${actual}"))
  }
}

proc remote_executor_sha256(metadata: Path, node: types.PlanNode) [fs, error] -> Result[Str] {
  let dto = json.read(metadata)?.require(RemoteMetadataDto)?

  if dto.name != node.name or dto.ver != node.ver or dto.rel != node.rel {
    return Err(types.PmError.PackageContract(f"remote metadata does not match plan node ${node.package_id}"))
  }

  # Legacy package metadata did not record an executor digest. Its verified metadata digest is a stable fallback.
  let raw: Record = json.read(metadata)?
  let value: Str = if raw.has("executor_sha256") { raw.get("executor_sha256")? } else { hash.sha256(metadata)?.hex() }
  require_sha256(value, "remote metadata executor_sha256")?
  value
}

proc remote_staged_artifact_for(
  node: types.PlanNode,
  retrieval: types.RemoteRetrieval,
  remote_repo: Str,
  cache: Path,
) [fs, net, error] -> Result[types.StagedArtifact] {
  require_key(node.artifact_key)?
  let cache_dir = fp"${cache}/${node.artifact_key}"
  let payload = fp"${cache_dir}/payload.tar.gz"
  let metadata = fp"${cache_dir}/metadata.json"
  let proof = fp"${cache_dir}/proof.json"
  fs.mkdir(cache_dir)?
  fetch_remote_object(remote_repo, fp"${retrieval.tarball}", payload, retrieval.tarball_sha256, "payload")?
  fetch_remote_object(remote_repo, fp"${retrieval.metadata}", metadata, retrieval.metadata_sha256, "metadata")?
  let executor_sha256 = remote_executor_sha256(metadata, node)?
  fs.write_atomic(
    proof,
    json.encode({
      format: "laputa-package-proof-1",
      origin: "remote",
      package_id: node.package_id,
      proof_key: node.proof_key,
      proof_input_sha256: node.proof_sha256,
      metadata_sha256: retrieval.metadata_sha256,
    })? + "\n",
  )?
  {payload, metadata, proof, executor_sha256}
}

proc remote_staged_artifact(node: types.PlanNode, remote_repo: Str, cache: Path) [fs, net, error] -> Result[types.StagedArtifact] {
  let retrieval = node.remote

  if retrieval != null {
    return remote_staged_artifact_for(node, retrieval, remote_repo, cache)
  }

  return Err(types.PmError.PackageContract(f"remote artifact ${node.package_id} has no retrieval coordinates"))
}

## Returns the canonical final directory for an artifact key. `path` is reserved by XSH's standard module namespace, so `artifact_path` is the strict-safe spelling.
export pure artifact_path(root: Path, key: Str) -> Path {
  fp"${object_root(root)}/${key}"
}

## Looks up one completed artifact and verifies every stored object before returning its receipt.
export proc lookup(root: Path, key: Str) [fs, error] -> Result[types.ArtifactReceipt] {
  verify_artifact(root, key)
}

## Re-verifies a receipt at its returned immutable artifact directory before another domain consumes its payload.
export proc verify_receipt(value: types.ArtifactReceipt) [fs, error] -> Result[types.ArtifactReceipt] {
  verify_dir(value.artifact_dir, value.key)
}

## Commits one locally built artifact through a locked temporary directory and an atomic final rename.
export proc commit(root: Path, node: types.PlanNode, staged: types.StagedArtifact) [fs, error] -> Result[types.ArtifactReceipt] {
  commit_staged(root, node, staged, types.Built)?
}

## Imports one exact remote artifact into the immutable store without re-resolving remote metadata.
export proc import_remote(
  root: Path,
  node: types.PlanNode,
  remote_repo: Str,
  cache: Path,
) [fs, net, error] -> Result[types.ArtifactReceipt] {
  let key = node.artifact_key
  require_key(key)?
  let lock_file = lock_path(root, key)
  fs.mkdir(lock_file.parent)?
  let lock = fs.lock(lock_file)?
  defer fs.unlock(lock)?

  if fs.exists(artifact_path(root, key))? {
    return verify_artifact(root, key)
  }

  commit_locked(root, node, remote_staged_artifact(node, remote_repo, cache)?, types.Remote)?
}

## Verifies a completed artifact receipt, its key, and hashes of payload, metadata, and proof objects.
## XSH currently lowers exported user-module procedures into one runtime symbol table: keeping this as `verify` would collide with the required `root.verify` when root imports this module. `verify_artifact` is therefore the unambiguous store boundary; no `verify` alias may be added.
export proc verify_artifact(root: Path, key: Str) [fs, error] -> Result[types.ArtifactReceipt] {
  require_key(key)?
  let final_dir = artifact_path(root, key)

  if ! fs.exists(final_dir)? {
    return Err(types.PmError.PackageTarball(f"artifact ${key} is missing"))
  }

  verify_dir(final_dir, key)
}
