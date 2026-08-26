##! Primitive-only generation adapter for external process owners.
# The published XSH runner gives a user module one process-wide tag namespace.
# Keep PM's typed BuildPlan, Store, and Generation values inside this module so
# an image/profile process can use the mounted PM checkout without importing a
# second identity for `pm.types`.
use execute as pm_execute
use generation as pm_generation
use plan_json as pm_plan_json
use remote as pm_remote
use store as pm_store
use types

error GenerationAdapterError = Failed(message: Str) : InvalidData

type GenerationAdapterArtifactDto = {package_name: Str, package_id: Str, artifact_key: Str}
type GenerationAdapterPlanDto = {
  format: Str,
  target: Str,
  build_plan_sha256: Str,
  profile: Str,
  overlay_sha256: Str,
  replacements: List[Str],
  runtime_roots: List[Str],
  artifacts: List[GenerationAdapterArtifactDto],
  generation_sha256: Str,
}
type GenerationAdapterMetadataFileDto = {path: Str, kind: Str, mode: Int, sha256: Str, target: Str}
type GenerationAdapterMetadataDto = {name: Str, ver: Str, rel: Str, package_kind: Str, files: List[GenerationAdapterMetadataFileDto]}

## The only PM-specific result exposed to an external image/profile process.
export type GenerationAdapterResult = {generation_root: Path}

pure generation_adapter_plan_dto(value: types.GenerationPlan) -> GenerationAdapterPlanDto {
  {
    format: value.format,
    target: types.target_text(value.target),
    build_plan_sha256: value.build_plan_sha256,
    profile: value.profile.name,
    overlay_sha256: value.profile.overlay_sha256,
    replacements: value.profile.replacements,
    runtime_roots: value.runtime_roots,
    artifacts: [{package_name: item.package_name, package_id: item.package_id, artifact_key: item.artifact_key} for item in value.artifacts],
    generation_sha256: value.generation_sha256,
  }
}

proc generation_adapter_plan(
  build_plan_path: Path,
  runtime_roots: List[Str],
  profile_name: Str,
  overlay_root: Path,
  output: Path,
) [fs, error] -> Result[types.GenerationPlan] {
  let build_plan = pm_plan_json.read(build_plan_path)?
  let profile = pm_generation.overlay_profile(overlay_root)?

  if profile.name != profile_name {
    return Err(GenerationAdapterError.Failed(f"overlay profile ${profile.name} does not match ${profile_name}"))
  }

  let generation = pm_generation.plan_profile(build_plan, runtime_roots, profile)?
  fs.write_atomic(output, json.encode(generation_adapter_plan_dto(generation))? + "\n")?
  generation
}

proc generation_adapter_publish_receipt(root: Path, expected: types.GenerationReceipt, output: Path) [fs, error] {
  let actual = pm_generation.read_generation_receipt(root)?

  if actual != expected {
    return Err(GenerationAdapterError.Failed("completed generation receipt does not match its plan"))
  }

  fs.write_atomic(output, fs.read_text(fp"${root}/var/lib/laputa/generation.json")?)?
}

proc generation_adapter_ensure_generation(
  value: types.GenerationPlan,
  store_root: Path,
  output_parent: Path,
  overlay_root: Path,
  receipt_output: Path,
) [fs, error] -> Result[types.GenerationReceipt] {
  let root = fp"${output_parent}/${value.generation_sha256}"

  if fs.exists(root)? {
    let receipt = pm_generation.read_generation_receipt(root)?
    if receipt.generation_sha256 != value.generation_sha256 or receipt.build_plan_sha256 != value.build_plan_sha256 {
      return Err(GenerationAdapterError.Failed(f"existing generation ${value.generation_sha256} does not match the saved plan"))
    }
    pm_generation.verify_generation(root, receipt)?
    generation_adapter_publish_receipt(root, receipt, receipt_output)?
    return receipt
  }

  let receipt = pm_generation.compose(value, store_root, root, overlay_root)?
  pm_generation.verify_generation(root, receipt)?
  generation_adapter_publish_receipt(root, receipt, receipt_output)?
  receipt
}

proc generation_adapter_require_no_forbidden_packages(receipt: types.GenerationReceipt, forbidden_packages: List[Str]) [error] {
  for artifact in receipt.artifacts {
    if artifact.package_name in forbidden_packages {
      return Err(GenerationAdapterError.Failed(f"generation includes forbidden package ${artifact.package_name}"))
    }
  }
}

# Validate the concrete executor result before this adapter crosses from PM's
# typed graph into the primitive-only profile process.
proc generation_adapter_completed_build(
  expected: types.BuildPlan,
  actual: types.BuildResult,
) [error] {
  if actual.format != "laputa-build-result-1" or actual.plan_sha256 != expected.plan_sha256 {
    return Err(GenerationAdapterError.Failed("executor result does not match the saved BuildPlan"))
  }

  let receipts: List[types.ArtifactReceipt] = actual.artifacts
  if receipts.len() != expected.nodes.len() {
    return Err(GenerationAdapterError.Failed("executor result does not contain one receipt per BuildPlan node"))
  }

  var index = 0
  while index < expected.nodes.len() {
    let node = expected.nodes[index]
    let receipt = receipts[index]
    if receipt.key != node.artifact_key or receipt.package_name != node.name or receipt.package_id != node.package_id {
      return Err(GenerationAdapterError.Failed("executor receipt does not match its BuildPlan node"))
    }
    index += 1
  }
}

proc generation_adapter_find_node(value: types.BuildPlan, package_name: Str) [error] -> Result[types.PlanNode] {
  for node in value.nodes {
    if node.name == package_name {
      return node
    }
  }

  Err(GenerationAdapterError.Failed(f"package ${package_name} is not in the saved BuildPlan"))
}

proc generation_adapter_manifest_file(
  metadata: GenerationAdapterMetadataDto,
  package_name: Str,
  package_path: Path,
) [error] -> Result[GenerationAdapterMetadataFileDto] {
  let path_text = package_path.display()
  if metadata.name != package_name {
    return Err(GenerationAdapterError.Failed(f"artifact metadata names ${metadata.name}, expected ${package_name}"))
  }

  for entry in metadata.files {
    if entry.path == path_text and (entry.kind == "file" or entry.kind == "binary") and entry.sha256 != "" {
      return entry
    }
  }

  Err(GenerationAdapterError.Failed(f"artifact metadata does not declare ${path_text}"))
}

## Copies one manifest-declared payload file only after its Store receipt and payload digest agree with the saved BuildPlan.
export proc generation_adapter_copy_manifest_file(
  build_plan_path: Path,
  store_root: Path,
  package_name: Str,
  package_path: Path,
  output: Path,
) [fs, error] {
  let build_plan = pm_plan_json.read(build_plan_path)?
  let node = generation_adapter_find_node(build_plan, package_name)?
  let receipt = pm_store.lookup(store_root, node.artifact_key)?

  if receipt.package_name != package_name or receipt.package_id != node.package_id or receipt.key != node.artifact_key {
    return Err(GenerationAdapterError.Failed("artifact receipt does not match the BuildPlan"))
  }

  let metadata = json.read(fp"${receipt.artifact_dir}/metadata.json")?.require(GenerationAdapterMetadataDto)?
  let manifest = generation_adapter_manifest_file(metadata, package_name, package_path)?
  let handle = fs.tempdir()?
  defer fs.close_root(handle)?
  let extracted = fs.root_path(handle)?
  archive.tar_extract(fp"${receipt.artifact_dir}/payload.tar.gz", extracted, 0, "auto", true)?
  let source = fp"${extracted}/${package_path.display()}"

  if ! fs.exists(source)? or fs.metadata(source)?.kind != "file" {
    return Err(GenerationAdapterError.Failed(f"artifact payload does not contain ${package_path.display()}"))
  }
  if hash.sha256(source)?.hex() != manifest.sha256 {
    return Err(GenerationAdapterError.Failed(f"artifact payload digest does not match metadata for ${package_path.display()}"))
  }

  let temporary = fp"${output}.tmp"
  fs.mkdir(output.parent)?
  fs.remove(temporary, missing_ok: true)?
  defer fs.remove(temporary, missing_ok: true)?
  fs.copy(source, temporary)?
  fs.fsync(temporary)?
  fs.rename(temporary, output, overwrite: true)?
}

## Executes a saved BuildPlan, then composes exactly its declared runtime generation.
export proc generation_adapter_execute_profile(
  build_plan_path: Path,
  repo_root: Path,
  store_root: Path,
  jobs: Int,
  runtime_roots: List[Str],
  profile_name: Str,
  overlay_root: Path,
  output_parent: Path,
  generation_plan_output: Path,
  generation_receipt_output: Path,
  forbidden_packages: List[Str],
) [fs, net, process, env, time, error] -> Result[GenerationAdapterResult] {
  let build_plan = pm_plan_json.read(build_plan_path)?
  let urls = pm_remote.load_repo_urls()?
  let remote_repo = if urls.repo != "" { urls.repo } else { urls.public_repo }
  let execution: types.BuildResult = pm_execute.build_plan(build_plan, repo_root, store_root, remote_repo, jobs)?
  generation_adapter_completed_build(build_plan, execution)?
  let generation = generation_adapter_plan(build_plan_path, runtime_roots, profile_name, overlay_root, generation_plan_output)?
  let receipt = generation_adapter_ensure_generation(generation, store_root, output_parent, overlay_root, generation_receipt_output)?
  generation_adapter_require_no_forbidden_packages(receipt, forbidden_packages)?
  {generation_root: fp"${output_parent}/${receipt.generation_sha256}"}
}

## Projects a saved BuildPlan to a generation-plan DTO without executing package artifacts.
export proc generation_adapter_plan_profile(
  build_plan_path: Path,
  runtime_roots: List[Str],
  profile_name: Str,
  overlay_root: Path,
  generation_plan_output: Path,
) [fs, error] {
  let _ = generation_adapter_plan(build_plan_path, runtime_roots, profile_name, overlay_root, generation_plan_output)?
}
