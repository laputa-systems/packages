##! Deterministic runtime-only system generations assembled from verified BuildPlan artifacts.
# `plan` is the generic boundary. Profile callers that own overlay replacement policy use
# `plan_profile`; `overlay_profile` decodes the explicit `overlay.json` metadata file.
use plan as build_plan
use root as pm_root
use store as artifact_store
use types
use util

type OverlayConfigDto = {format: Str, profile: Str, replacements: List[Str]}
type GenerationArtifactDto = {package_name: Str, package_id: Str, artifact_key: Str}
type GenerationReceiptDto = {
  format: Str,
  generation_sha256: Str,
  build_plan_sha256: Str,
  profile: Str,
  overlay_sha256: Str,
  replacements: List[Str],
  target: Str,
  runtime_roots: List[Str],
  artifacts: List[GenerationArtifactDto],
  root_sha256: Str,
}
type GenerationOverlayEntry = {path: Str, source: Path, kind: Str, mode: Int, sha256: Str, target: Str}

pure generation_format() -> Str {
  "laputa-generation-plan-1"
}

pure generation_receipt_format() -> Str {
  "laputa-generation-1"
}

pure generation_overlay_config_path(overlay_root: Path) -> Path {
  fp"${overlay_root}/overlay.json"
}

pure generation_receipt_path(output_root: Path) -> Path {
  fp"${output_root}/var/lib/laputa/generation.json"
}

pure generation_empty_overlay_sha256() -> Str {
  bytes.from_text("format\tlaputa-generation-overlay-1\n").sha256().hex()
}

pure generation_sha256_text_is_valid(value: Str) -> Bool {
  value.count_chars() == 64 and value == value.lower() and value.delete("0123456789abcdef") == ""
}

proc generation_require_sha256(value: Str, label: Str) [error] {
  if ! generation_sha256_text_is_valid(value) {
    return Err(types.PmError.PackageContract(f"${label} must be a lowercase SHA-256 digest"))
  }
}

pure generation_canonical_field(value: Str) -> Str {
  value.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")
}

pure generation_sorted_unique(values: List[Str]) -> List[Str] {
  var result: List[Str] = []
  var seen: Map[Bool] = {}

  for value in values |> sort {
    if ! seen.get(value, false) {
      result = result.push(value)
      seen[value] = true
    }
  }

  result
}

proc generation_require_profile_name(value: Str) [error] {
  if value == "" or value.contains("/") or value.contains("\\") or value.contains("\n") {
    return Err(types.PmError.PackageContract(f"generation profile name is invalid: ${value}"))
  }
}

proc generation_require_overlay_path(value: Str, label: Str) [error] {
  if value == "" or value == "." {
    return Err(types.PmError.PackageContract(f"${label} must not be empty"))
  }

  let normalized = util.ensure_relative_path(fp"${value}", label)?

  if normalized.display() != value {
    return Err(types.PmError.PackageContract(f"${label} must be canonical and relative: ${value}"))
  }
}

proc generation_validate_symlink_target(path_value: Str, target: Str) [error] {
  if target == "" or target.starts_with("/") {
    return Err(types.PmError.PackageContract(f"overlay symlink ${path_value} has an invalid target ${target}"))
  }

  var depth = path_value.split("/").len() - 1

  for component in target.split("/") {
    if component == "" {
      return Err(types.PmError.PackageContract(f"overlay symlink ${path_value} has an invalid target ${target}"))
    }

    if component == "." {
      continue
    }

    if component == ".." {
      if depth == 0 {
        return Err(types.PmError.PackageContract(f"overlay symlink ${path_value} escapes the generation: ${target}"))
      }

      depth -= 1
    } else {
      depth += 1
    }
  }
}

proc generation_validate_profile(value: types.GenerationProfile) [error] {
  generation_require_profile_name(value.name)?
  generation_require_sha256(value.overlay_sha256, "generation overlay_sha256")?
  let replacements = generation_sorted_unique(value.replacements)

  if replacements != value.replacements {
    return Err(types.PmError.PackageContract("generation profile replacements must be sorted and unique"))
  }

  for replacement in value.replacements {
    generation_require_overlay_path(replacement, "generation profile replacement")?

    if replacement == "overlay.json" or replacement == "var/lib/laputa/generation.json" or replacement == "var/lib/laputa/root.json" {
      return Err(types.PmError.PackageContract(f"generation profile may not replace reserved ${replacement}"))
    }
  }
}

proc generation_digest(value: types.GenerationPlan) [error] -> Result[Str] {
  var lines = [
    "format\tlaputa-generation-fingerprint-1",
    f"generation-format\t${generation_canonical_field(value.format)}",
    f"target\t${types.target_text(value.target)}",
    f"build-plan\t${value.build_plan_sha256}",
    f"profile\t${generation_canonical_field(value.profile.name)}",
    f"overlay\t${value.profile.overlay_sha256}",
  ]

  for root in value.runtime_roots {
    lines = lines.push(f"runtime-root\t${generation_canonical_field(root)}")
  }

  for replacement in value.profile.replacements {
    lines = lines.push(f"replacement\t${generation_canonical_field(replacement)}")
  }

  for artifact in value.artifacts {
    lines = lines.push(
      f"artifact\t${generation_canonical_field(artifact.package_name)}\t${generation_canonical_field(artifact.package_id)}\t${artifact.artifact_key}",
    )
  }

  bytes.from_text(lines.join("\n") + "\n").sha256().hex()
}

proc generation_validate_plan(value: types.GenerationPlan) [error] {
  if value.format != generation_format() {
    return Err(types.PmError.PackageContract(f"unsupported generation plan format ${value.format}"))
  }

  if value.target != types.Aarch64LinuxMusl {
    return Err(types.PmError.PackageContract("generation plan must target aarch64-linux-musl"))
  }

  generation_require_sha256(value.build_plan_sha256, "generation build_plan_sha256")?
  generation_validate_profile(value.profile)?

  let canonical_roots = generation_sorted_unique(value.runtime_roots)

  if value.runtime_roots.len() == 0 or value.runtime_roots != canonical_roots {
    return Err(types.PmError.PackageContract("generation runtime roots must be non-empty, sorted, and unique"))
  }

  var names: Map[Bool] = {}
  var keys: Map[Bool] = {}
  var prior_name = ""

  for artifact in value.artifacts {
    if artifact.package_name == "" or artifact.package_id == "" {
      return Err(types.PmError.PackageContract("generation artifact package identity is incomplete"))
    }

    generation_require_sha256(artifact.artifact_key, f"generation artifact ${artifact.package_name} key")?

    if names.has(artifact.package_name) or keys.has(artifact.artifact_key) {
      return Err(types.PmError.PackageContract(f"generation plan repeats artifact ${artifact.package_name}"))
    }

    if prior_name != "" and artifact.package_name < prior_name {
      return Err(types.PmError.PackageContract("generation artifacts are not in canonical order"))
    }

    names[artifact.package_name] = true
    keys[artifact.artifact_key] = true
    prior_name = artifact.package_name
  }

  for root in value.runtime_roots {
    if ! names.has(root) {
      return Err(types.PmError.PackageContract(f"generation runtime root ${root} is not selected"))
    }
  }

  if value.generation_sha256 != generation_digest(value)? {
    return Err(types.PmError.PackageContract("generation plan digest does not match its canonical inputs"))
  }
}

proc generation_runtime_artifacts(
  value: types.BuildPlan,
  runtime_roots: List[Str],
) [error] -> Result[List[types.GenerationArtifact]] {
  var nodes: Map[types.PlanNode] = {}

  for node in value.nodes {
    nodes[node.name] = node
  }

  var selected: Map[Bool] = {}
  var pending = runtime_roots
  var pending_index = 0
  var artifacts: List[types.GenerationArtifact] = []

  while pending_index < pending.len() {
    let name = pending[pending_index]
    pending_index += 1

    if selected.get(name, false) {
      continue
    }

    if ! nodes.has(name) {
      return Err(types.PmError.MissingDependency(f"generation runtime root ${name} is not in the BuildPlan"))
    }

    let node: types.PlanNode = nodes.get(name)?
    selected[name] = true
    artifacts = artifacts.push({package_name: node.name, package_id: node.package_id, artifact_key: node.artifact_key})

    # BuildPlan dependencies are the typed graph projection; only Runtime edges reach a system root.
    for dependency in node.dependencies {
      if dependency.kind == types.Runtime and ! selected.get(dependency.name, false) {
        pending = pending.push(dependency.name)
      }
    }
  }

  artifacts |> sort-by .package_name
}

## Plans a generic default-profile generation from explicit runtime roots and an already-computed overlay tree digest.
export proc plan(
  value: types.BuildPlan,
  runtime_roots: List[Str],
  overlay_digest: Str,
) [error] -> Result[types.GenerationPlan] {
  plan_profile(
    value,
    runtime_roots,
    {name: "default", overlay_sha256: overlay_digest, replacements: []},
  )
}

## Plans a profile-owned generation, including the explicit overlay replacement declaration in its identity.
export proc plan_profile(
  value: types.BuildPlan,
  runtime_roots: List[Str],
  profile: types.GenerationProfile,
) [error] -> Result[types.GenerationPlan] {
  build_plan.validate(value)?
  generation_validate_profile(profile)?
  let roots = generation_sorted_unique(runtime_roots)

  if roots.len() == 0 {
    return Err(types.PmError.Usage("generation plan needs one or more runtime roots"))
  }

  let bare: types.GenerationPlan = {
    format: generation_format(),
    target: value.target,
    build_plan_sha256: value.plan_sha256,
    profile,
    runtime_roots: roots,
    artifacts: generation_runtime_artifacts(value, roots)?,
    generation_sha256: "",
  }
  let planned = {...bare, generation_sha256: generation_digest(bare)?}
  generation_validate_plan(planned)?
  planned
}

## Decodes profile-owned overlay metadata. An overlay without `overlay.json` is the strict default profile with no replacements.
export proc overlay_profile(overlay_root: Path) [fs, error] -> Result[types.GenerationProfile] {
  let config = generation_overlay_config_path(overlay_root)

  if ! fs.exists(config)? {
    return {name: "default", overlay_sha256: overlay_digest(overlay_root)?, replacements: []}
  }

  if fs.metadata(config)?.kind != "file" {
    return Err(types.PmError.PackageContract("generation overlay.json must be a file"))
  }

  let dto = json.read(config)?.require(OverlayConfigDto)?

  if dto.format != "laputa-generation-overlay-1" {
    return Err(types.PmError.PackageContract(f"unsupported generation overlay format ${dto.format}"))
  }

  let profile = {name: dto.profile, overlay_sha256: overlay_digest(overlay_root)?, replacements: dto.replacements}
  generation_validate_profile(profile)?
  profile
}

## Computes the canonical content identity of a profile overlay, including its explicit `overlay.json` policy metadata.
export proc overlay_digest(overlay_root: Path) [fs, error] -> Result[Str] {
  if ! fs.exists(overlay_root)? {
    return generation_empty_overlay_sha256()
  }

  if fs.metadata(overlay_root)?.kind != "dir" {
    return Err(types.PmError.PackageContract(f"generation overlay ${overlay_root.display()} must be a directory"))
  }

  var lines = ["format\tlaputa-generation-overlay-1"]

  for entry in fs.walk(overlay_root, gitignore: false, hidden: true) |> sort-by .path {
    let relative = entry.path.strip_prefix(overlay_root)?.display()
    continue when relative == "."
    generation_require_overlay_path(relative, "generation overlay path")?

    if relative == ".git" or relative.starts_with(".git/") {
      return Err(types.PmError.PackageContract("generation overlay may not contain .git"))
    }

    let metadata = fs.metadata(entry.path)?
    let mode = metadata.mode % 4096

    if metadata.kind == "file" {
      lines = lines.push(f"file\t${generation_canonical_field(relative)}\t${mode}\t${hash.sha256(entry.path)?.hex()}")
    } else if metadata.kind == "dir" {
      lines = lines.push(f"dir\t${generation_canonical_field(relative)}\t${mode}")
    } else if metadata.kind == "symlink" {
      let target = entry.path.readlink()?.display()
      generation_validate_symlink_target(relative, target)?
      lines = lines.push(f"symlink\t${generation_canonical_field(relative)}\t${mode}\t${generation_canonical_field(target)}")
    } else {
      return Err(types.PmError.PackageContract(f"generation overlay has unsupported ${metadata.kind} ${relative}"))
    }
  }

  bytes.from_text(lines.join("\n") + "\n").sha256().hex()
}

proc generation_overlay_entries(overlay_root: Path) [fs, error] -> Result[List[GenerationOverlayEntry]] {
  if ! fs.exists(overlay_root)? or fs.metadata(overlay_root)?.kind != "dir" {
    return Err(types.PmError.PackageContract(f"generation overlay ${overlay_root.display()} must be a directory"))
  }

  var entries: List[GenerationOverlayEntry] = []

  for entry in fs.walk(overlay_root, gitignore: false, hidden: true) |> sort-by .path {
    let relative = entry.path.strip_prefix(overlay_root)?.display()
    continue when relative == "." or relative == "overlay.json"
    generation_require_overlay_path(relative, "generation overlay path")?

    if relative == ".git" or relative.starts_with(".git/") {
      return Err(types.PmError.PackageContract("generation overlay may not contain .git"))
    }

    let metadata = fs.metadata(entry.path)?
    let mode = metadata.mode % 4096

    if metadata.kind == "file" {
      entries = entries.push({path: relative, source: entry.path, kind: "file", mode, sha256: hash.sha256(entry.path)?.hex(), target: ""})
    } else if metadata.kind == "dir" {
      entries = entries.push({path: relative, source: entry.path, kind: "dir", mode, sha256: "", target: ""})
    } else if metadata.kind == "symlink" {
      let target = entry.path.readlink()?.display()
      generation_validate_symlink_target(relative, target)?
      entries = entries.push({path: relative, source: entry.path, kind: "symlink", mode, sha256: "", target})
    } else {
      return Err(types.PmError.PackageContract(f"generation overlay has unsupported ${metadata.kind} ${relative}"))
    }
  }

  entries
}

proc generation_preflight_overlay(
  entries: List[GenerationOverlayEntry],
  root_plan: types.RootPlan,
  profile: types.GenerationProfile,
) [error] {
  var used_replacements: Map[Bool] = {}

  for entry in entries {
    if entry.path == "var/lib/laputa/root.json" or entry.path == "var/lib/laputa/generation.json" {
      return Err(types.PmError.PackageContract(f"generation overlay may not own reserved ${entry.path}"))
    }

    for package_entry in root_plan.entries {
      if entry.path == package_entry.path {
        if package_entry.kind == types.Tree or entry.kind == "dir" or entry.path not in profile.replacements {
          return Err(types.PmError.PackageConflict(f"generation overlay ${entry.path} conflicts with package ${package_entry.package_name}"))
        }

        used_replacements[entry.path] = true
      } else if entry.path.starts_with(f"${package_entry.path}/") and package_entry.kind != types.Tree {
        return Err(types.PmError.PackageConflict(f"generation overlay ${entry.path} conflicts below package file ${package_entry.path}"))
      } else if package_entry.path.starts_with(f"${entry.path}/") and entry.kind != "dir" {
        return Err(types.PmError.PackageConflict(f"generation overlay ${entry.path} conflicts above package path ${package_entry.path}"))
      }
    }
  }

  for replacement in profile.replacements {
    if ! used_replacements.has(replacement) {
      return Err(types.PmError.PackageContract(f"generation profile replacement ${replacement} does not replace a package file"))
    }
  }
}

proc generation_store_artifacts(
  value: types.GenerationPlan,
  store_root: Path,
) [fs, error] -> Result[List[types.ArtifactReceipt]] {
  var receipts: List[types.ArtifactReceipt] = []
  var keys: Map[Bool] = {}

  for artifact in value.artifacts {
    let receipt = artifact_store.lookup(store_root, artifact.artifact_key)?

    if receipt.target != value.target or receipt.package_name != artifact.package_name or receipt.package_id != artifact.package_id or receipt.key != artifact.artifact_key {
      return Err(types.PmError.PackageContract(f"generation artifact ${artifact.package_name} does not match its verified Store receipt"))
    }

    keys[receipt.key] = true
    receipts = receipts.push(receipt)
  }

  for receipt in receipts {
    for dependency_key in receipt.runtime_dependency_keys {
      if ! keys.has(dependency_key) {
        return Err(types.PmError.MissingDependency(f"generation artifact ${receipt.package_name} is missing runtime artifact ${dependency_key}"))
      }
    }
  }

  receipts |> sort-by .package_name
}

proc generation_apply_overlay(output_root: Path, entries: List[GenerationOverlayEntry]) [fs, error] {
  for entry in entries {
    let destination = fp"${output_root}/${entry.path}"

    if entry.kind == "dir" {
      if fs.exists(destination)? {
        if fs.metadata(destination)?.kind != "dir" {
          return Err(types.PmError.PackageConflict(f"generation overlay directory ${entry.path} cannot replace a non-directory"))
        }
      } else {
        fs.mkdir(destination)?
      }

      fs.chmod(destination, entry.mode)?
    } else {
      fs.mkdir(destination.parent)?

      if fs.exists(destination)? {
        fs.remove(destination)?
      }

      if entry.kind == "file" {
        fs.copy(entry.source, destination)?
        fs.chmod(destination, entry.mode)?
      } else if entry.kind == "symlink" {
        fs.symlink(fp"${entry.target}", destination)?
      } else {
        return Err(types.PmError.PackageContract(f"generation overlay has invalid entry ${entry.path}"))
      }
    }
  }
}

pure generation_artifact_dto(value: types.GenerationArtifact) -> GenerationArtifactDto {
  {package_name: value.package_name, package_id: value.package_id, artifact_key: value.artifact_key}
}

pure generation_receipt_dto(value: types.GenerationReceipt) -> GenerationReceiptDto {
  {
    format: value.format,
    generation_sha256: value.generation_sha256,
    build_plan_sha256: value.build_plan_sha256,
    profile: value.profile.name,
    overlay_sha256: value.profile.overlay_sha256,
    replacements: value.profile.replacements,
    target: types.target_text(value.target),
    runtime_roots: value.runtime_roots,
    artifacts: [generation_artifact_dto(artifact) for artifact in value.artifacts],
    root_sha256: value.root_sha256,
  }
}

proc generation_artifact_from_dto(value: GenerationArtifactDto) [] -> types.GenerationArtifact {
  {package_name: value.package_name, package_id: value.package_id, artifact_key: value.artifact_key}
}

proc generation_receipt_from_dto(value: GenerationReceiptDto) [error] -> Result[types.GenerationReceipt] {
  {
    format: value.format,
    generation_sha256: value.generation_sha256,
    build_plan_sha256: value.build_plan_sha256,
    profile: {name: value.profile, overlay_sha256: value.overlay_sha256, replacements: value.replacements},
    target: types.parse_target(value.target)?,
    runtime_roots: value.runtime_roots,
    artifacts: [generation_artifact_from_dto(artifact) for artifact in value.artifacts],
    root_sha256: value.root_sha256,
  }
}

proc generation_validate_receipt(value: types.GenerationReceipt) [error] {
  let plan: types.GenerationPlan = {
    format: generation_format(),
    target: value.target,
    build_plan_sha256: value.build_plan_sha256,
    profile: value.profile,
    runtime_roots: value.runtime_roots,
    artifacts: value.artifacts,
    generation_sha256: value.generation_sha256,
  }

  if value.format != generation_receipt_format() {
    return Err(types.PmError.PackageContract(f"unsupported generation receipt format ${value.format}"))
  }

  generation_require_sha256(value.root_sha256, "generation root_sha256")?
  generation_validate_plan(plan)?
}

proc generation_receipt_for(value: types.GenerationPlan, root_receipt: types.RootReceipt) [error] -> Result[types.GenerationReceipt] {
  generation_validate_plan(value)?

  if root_receipt.target != value.target {
    return Err(types.PmError.PackageContract("generation root receipt target does not match the generation plan"))
  }

  {
    format: generation_receipt_format(),
    generation_sha256: value.generation_sha256,
    build_plan_sha256: value.build_plan_sha256,
    profile: value.profile,
    target: value.target,
    runtime_roots: value.runtime_roots,
    artifacts: value.artifacts,
    root_sha256: root_receipt.root_sha256,
  }
}

## Reads and validates a completed generation receipt without consulting a package repository.
export proc read_generation_receipt(output_root: Path) [fs, error] -> Result[types.GenerationReceipt] {
  let dto = json.read(generation_receipt_path(output_root))?.require(GenerationReceiptDto)?
  let receipt = generation_receipt_from_dto(dto)?
  generation_validate_receipt(receipt)?
  receipt
}

## Composes a complete runtime generation after Store, package-root, and overlay ownership preflight succeeds.
export proc compose(
  value: types.GenerationPlan,
  store_root: Path,
  output_root: Path,
  overlay_root: Path,
) [fs, error] -> Result[types.GenerationReceipt] {
  generation_validate_plan(value)?
  let actual_overlay_sha256 = overlay_digest(overlay_root)?

  if actual_overlay_sha256 != value.profile.overlay_sha256 {
    return Err(types.PmError.PackageContract("generation overlay digest does not match the plan"))
  }

  let actual_profile = overlay_profile(overlay_root)?

  if actual_profile != value.profile {
    return Err(types.PmError.PackageContract("generation overlay profile metadata does not match the plan"))
  }

  let artifacts = generation_store_artifacts(value, store_root)?
  let root_plan = pm_root.preflight(artifacts)?
  let entries = generation_overlay_entries(overlay_root)?
  generation_preflight_overlay(entries, root_plan, value.profile)?

  if fs.exists(output_root)? {
    return Err(types.PmError.PackageConflict(f"immutable generation ${output_root.display()} already exists"))
  }

  let temporary = fp"${output_root}.tmp"
  fs.remove(temporary, missing_ok: true)?
  defer fs.remove(temporary, missing_ok: true)?
  let root_receipt = pm_root.compose_artifacts(temporary, root_plan, artifacts)?
  generation_apply_overlay(temporary, entries)?
  let receipt = generation_receipt_for(value, root_receipt)?
  let receipt_path = generation_receipt_path(temporary)
  fs.mkdir(receipt_path.parent)?
  fs.write(receipt_path, json.encode(generation_receipt_dto(receipt))? + "\n")?
  let stored = read_generation_receipt(temporary)?

  if stored != receipt {
    return Err(types.PmError.PackageContract("generation receipt changed while composing"))
  }

  fs.mkdir(output_root.parent)?
  fs.rename(temporary, output_root)?
  let final_receipt = read_generation_receipt(output_root)?

  if final_receipt != receipt {
    return Err(types.PmError.PackageContract("completed generation receipt does not match"))
  }

  receipt
}

## Verifies that a completed generation still carries its exact immutable receipt.
export proc verify_generation(output_root: Path, expected: types.GenerationReceipt) [fs, error] {
  generation_validate_receipt(expected)?
  let stored = read_generation_receipt(output_root)?

  if stored != expected {
    return Err(types.PmError.PackageContract("generation receipt does not match the completed generation"))
  }
}
