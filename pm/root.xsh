##! Deterministic immutable root plans composed only from verified artifact-store receipts.
use store as artifact_store
use types
use util

type ArtifactEntryDto = {path: Str, kind: Str, mode: Int, sha256: Str, target: Str}
type ArtifactMetadataDto = {name: Str, ver: Str, rel: Str, package_kind: Str, files: List[ArtifactEntryDto]}
type RootArtifactDto = {package_name: Str, package_id: Str, artifact_key: Str, payload: Bool}
type RootEntryDto = {
  package_name: Str,
  package_id: Str,
  artifact_key: Str,
  path: Str,
  kind: Str,
  mode: Int,
  sha256: Str,
  target: Str,
}
type RootReceiptDto = {
  format: Str,
  target: Str,
  artifacts: List[RootArtifactDto],
  entries: List[RootEntryDto],
  root_sha256: Str,
}
type DecodedArtifactMetadata = {kind: types.PackageKind, entries: List[types.ArtifactEntry]}

pure root_receipt_path(output: Path) -> Path {
  fp"${output}/var/lib/laputa/root.json"
}

pure root_sha256_text_is_valid(value: Str) -> Bool {
  value.count_chars() == 64 and value == value.lower() and value.delete("0123456789abcdef") == ""
}

proc root_require_sha256(value: Str, label: Str) [error] {
  if ! root_sha256_text_is_valid(value) {
    return Err(types.PmError.PackageContract(f"${label} must be a lowercase SHA-256 digest"))
  }
}

proc root_require_relative_path(value: Str, label: Str) [error] {
  if value == "" or value == "." {
    return Err(types.PmError.PackageContract(f"${label} must not be empty"))
  }

  let normalized = util.ensure_relative_path(fp"${value}", label)?

  if normalized.display() != value {
    return Err(types.PmError.PackageContract(f"${label} must be canonical and relative: ${value}"))
  }
}

proc root_validate_symlink_target(path_value: Str, target: Str) [error] {
  if target == "" or target.starts_with("/") {
    return Err(types.PmError.PackageContract(f"symlink ${path_value} has an invalid target ${target}"))
  }

  var depth = path_value.split("/").len() - 1

  for component in target.split("/") {
    if component == "" {
      return Err(types.PmError.PackageContract(f"symlink ${path_value} has an invalid target ${target}"))
    }

    if component == "." {
      continue
    }

    if component == ".." {
      if depth == 0 {
        return Err(types.PmError.PackageContract(f"symlink ${path_value} escapes the root: ${target}"))
      }

      depth -= 1
    } else {
      depth += 1
    }
  }
}

proc root_decode_metadata_entry(value: ArtifactEntryDto) [error] -> Result[types.ArtifactEntry] {
  {
    path: value.path,
    kind: types.parse_file_kind(value.kind)?,
    mode: value.mode,
    sha256: value.sha256,
    target: value.target,
  }
}

proc root_validate_metadata_entry(value: types.ArtifactEntry) [error] {
  root_require_relative_path(value.path, "artifact metadata path")?

  if value.path == "var/lib/laputa/root.json" {
    return Err(types.PmError.PackageContract("artifact metadata may not own var/lib/laputa/root.json"))
  }

  if value.mode < 0 or value.mode > 0o777 {
    return Err(types.PmError.PackageContract(f"artifact metadata mode for ${value.path} is invalid"))
  }

  if value.kind == types.File or value.kind == types.Binary {
    if value.target != "" {
      return Err(types.PmError.PackageContract(f"file ${value.path} must not have a symlink target"))
    }

    root_require_sha256(value.sha256, f"file ${value.path} SHA-256")?
  } else if value.kind == types.Tree {
    if value.sha256 != "" or value.target != "" {
      return Err(types.PmError.PackageContract(f"directory ${value.path} must not have a hash or target"))
    }
  } else if value.kind == types.Symlink {
    if value.sha256 != "" {
      return Err(types.PmError.PackageContract(f"symlink ${value.path} must not have a file hash"))
    }

    root_validate_symlink_target(value.path, value.target)?
  }
}

proc root_artifact_metadata(receipt: types.ArtifactReceipt) [fs, error] -> Result[DecodedArtifactMetadata] {
  let dto = json.read(fp"${receipt.artifact_dir}/metadata.json")?.require(ArtifactMetadataDto)?
  let expected_id = util.package_id(dto.name, dto.ver, dto.rel)

  if dto.name != receipt.package_name or expected_id != receipt.package_id {
    return Err(types.PmError.PackageContract(f"artifact metadata does not match receipt ${receipt.package_id}"))
  }

  let kind = types.parse_package_kind(dto.package_kind)?
  var entries: List[types.ArtifactEntry] = []
  var seen: Map[Bool] = {}

  for raw in dto.files {
    let entry = root_decode_metadata_entry(raw)?
    root_validate_metadata_entry(entry)?

    if seen.has(entry.path) {
      return Err(types.PmError.PackageContract(f"artifact metadata repeats ${entry.path} for ${receipt.package_name}"))
    }

    seen[entry.path] = true
    entries = entries.push(entry)
  }

  if kind == types.Meta and entries.len() != 0 {
    return Err(types.PmError.PackageContract(f"metapackage ${receipt.package_name} must have no payload entries"))
  }

  {kind, entries: entries |> sort-by .path}
}

proc root_verify_entry_at(root: Path, entry: types.RootEntry) [fs, error] {
  let root_handle = fs.open_root(root)?
  defer fs.close_root(root_handle)
  let rel = fp"${entry.path}"
  let meta = fs.root_metadata(root_handle, rel)?

  if entry.kind == types.File or entry.kind == types.Binary {
    if meta.mode % 4096 != entry.mode {
      return Err(types.PmError.PackageContract(f"root entry ${entry.path} mode does not match metadata"))
    }

    if meta.kind != "file" or fs.root_read(root_handle, rel)?.sha256().hex() != entry.sha256 {
      return Err(types.PmError.PackageContract(f"root file ${entry.path} does not match metadata"))
    }
  } else if entry.kind == types.Tree {
    if meta.kind != "dir" {
      return Err(types.PmError.PackageContract(f"root directory ${entry.path} does not match metadata"))
    }
  } else if entry.kind == types.Symlink {
    let target = fs.root_readlink(root_handle, rel)?

    if target.display() != entry.target {
      return Err(types.PmError.PackageContract(f"root symlink ${entry.path} does not match metadata"))
    }
  }
}

proc root_verify_payload_entries(receipt: types.ArtifactReceipt, entries: List[types.RootEntry]) [fs, error] {
  let sandbox = fs.tempdir()?
  defer fs.close_root(sandbox)?
  let sandbox_path = fs.root_path(sandbox)?
  let extracted = fp"${sandbox_path}/payload"
  archive.tar_extract(fp"${receipt.artifact_dir}/payload.tar.gz", extracted)?
  var expected: Map[Bool] = {}

  for entry in entries {
    expected[entry.path] = true
    root_verify_entry_at(extracted, entry)?
  }

  for actual in fs.walk(extracted) {
    let rel = actual.path.strip_prefix(extracted)?
    var owned = actual.kind == "file" or actual.kind == "symlink"

    if actual.kind == "dir" and rel.display() != "." {
      var empty = true

      for _ in fs.ls(actual.path)? {
        empty = false
        break
      }

      owned = empty
    }

    if owned and ! expected.has(rel.display()) {
      return Err(types.PmError.PackageContract(f"artifact ${receipt.package_name} payload contains undeclared ${rel.display()}"))
    }
  }
}

proc root_verified_artifacts(artifacts: List[types.ArtifactReceipt]) [fs, error] -> Result[List[types.ArtifactReceipt]] {
  var verified: List[types.ArtifactReceipt] = []
  var keys: Map[Bool] = {}
  var names: Map[Bool] = {}

  for artifact in artifacts {
    let receipt = artifact_store.verify_receipt(artifact)?

    if keys.has(receipt.key) {
      return Err(types.PmError.PackageContract(f"duplicate artifact key ${receipt.key}"))
    }

    if names.has(receipt.package_name) {
      return Err(types.PmError.PackageContract(f"duplicate package ${receipt.package_name} in root artifacts"))
    }

    keys[receipt.key] = true
    names[receipt.package_name] = true
    verified = verified.push(receipt)
  }

  for receipt in verified {
    for dependency_key in receipt.runtime_dependency_keys {
      if ! keys.has(dependency_key) {
        return Err(types.PmError.MissingDependency(f"${receipt.package_name} runtime dependency artifact ${dependency_key} is absent"))
      }
    }
  }

  verified |> sort-by .package_name
}

pure root_digest(target: types.Target, artifacts: List[types.RootArtifact], entries: List[types.RootEntry]) -> Str {
  var lines = [f"target\t${types.target_text(target)}"]

  for artifact in artifacts {
    lines = lines.push(
      f"artifact\t${artifact.package_name}\t${artifact.package_id}\t${artifact.artifact_key}\t${if artifact.payload { "payload" } else { "meta" }}",
    )
  }

  for entry in entries {
    lines = lines.push(
      f"entry\t${entry.package_name}\t${entry.package_id}\t${entry.artifact_key}\t${entry.path}\t${types.file_kind_text(entry.kind)}\t${entry.mode}\t${entry.sha256}\t${entry.target}",
    )
  }

  bytes.from_text(lines.join("\n") + "\n").sha256().hex()
}

proc root_validate_plan(value: types.RootPlan) [error] {
  if value.format != "laputa-root-plan-1" {
    return Err(types.PmError.PackageContract(f"unsupported root plan format ${value.format}"))
  }

  if value.target != types.Aarch64LinuxMusl {
    return Err(types.PmError.PackageContract("root plan must target aarch64-linux-musl"))
  }

  var artifacts = value.artifacts
  var entries = value.entries
  artifacts = artifacts |> sort-by .package_name
  entries = entries |> sort-by .path

  if artifacts != value.artifacts or entries != value.entries {
    return Err(types.PmError.PackageContract("root plan is not in canonical order"))
  }

  if value.root_sha256 != root_digest(value.target, value.artifacts, value.entries) {
    return Err(types.PmError.PackageContract("root plan digest does not match"))
  }
}

pure root_artifact_dto(value: types.RootArtifact) -> RootArtifactDto {
  {package_name: value.package_name, package_id: value.package_id, artifact_key: value.artifact_key, payload: value.payload}
}

pure root_entry_dto(value: types.RootEntry) -> RootEntryDto {
  {
    package_name: value.package_name,
    package_id: value.package_id,
    artifact_key: value.artifact_key,
    path: value.path,
    kind: types.file_kind_text(value.kind),
    mode: value.mode,
    sha256: value.sha256,
    target: value.target,
  }
}

proc root_artifact_from_dto(value: RootArtifactDto) [error] -> Result[types.RootArtifact] {
  {package_name: value.package_name, package_id: value.package_id, artifact_key: value.artifact_key, payload: value.payload}
}

proc root_entry_from_dto(value: RootEntryDto) [error] -> Result[types.RootEntry] {
  {
    package_name: value.package_name,
    package_id: value.package_id,
    artifact_key: value.artifact_key,
    path: value.path,
    kind: types.parse_file_kind(value.kind)?,
    mode: value.mode,
    sha256: value.sha256,
    target: value.target,
  }
}

pure root_receipt_dto(value: types.RootReceipt) -> RootReceiptDto {
  {
    format: value.format,
    target: types.target_text(value.target),
    artifacts: [root_artifact_dto(artifact) for artifact in value.artifacts],
    entries: [root_entry_dto(entry) for entry in value.entries],
    root_sha256: value.root_sha256,
  }
}

proc root_receipt_from_dto(value: RootReceiptDto) [error] -> Result[types.RootReceipt] {
  var artifacts: List[types.RootArtifact] = []
  var entries: List[types.RootEntry] = []

  for artifact in value.artifacts {
    artifacts = artifacts.push(root_artifact_from_dto(artifact)?)
  }

  for entry in value.entries {
    entries = entries.push(root_entry_from_dto(entry)?)
  }

  {format: value.format, target: types.parse_target(value.target)?, artifacts, entries, root_sha256: value.root_sha256}
}

proc root_validate_receipt(value: types.RootReceipt) [error] {
  let plan: types.RootPlan = {
    format: "laputa-root-plan-1",
    target: value.target,
    artifacts: value.artifacts,
    entries: value.entries,
    root_sha256: value.root_sha256,
  }

  if value.format != "laputa-root-1" {
    return Err(types.PmError.PackageContract(f"unsupported root receipt format ${value.format}"))
  }

  root_validate_plan(plan)?
}

proc root_receipt_for_plan(value: types.RootPlan) [error] -> Result[types.RootReceipt] {
  root_validate_plan(value)?
  {format: "laputa-root-1", target: value.target, artifacts: value.artifacts, entries: value.entries, root_sha256: value.root_sha256}
}

proc root_read_receipt(output: Path) [fs, error] -> Result[types.RootReceipt] {
  let dto = json.read(root_receipt_path(output))?.require(RootReceiptDto)?
  let value = root_receipt_from_dto(dto)?
  root_validate_receipt(value)?
  value
}

## Builds and verifies the complete ownership, runtime closure, metadata, and payload contract before root mutation.
export proc preflight(artifacts: List[types.ArtifactReceipt]) [fs, error] -> Result[types.RootPlan] {
  let verified = root_verified_artifacts(artifacts)?
  var planned_artifacts: List[types.RootArtifact] = []
  var entries: List[types.RootEntry] = []

  for receipt in verified {
    let metadata = root_artifact_metadata(receipt)?
    let payload = metadata.kind != types.Meta
    planned_artifacts = planned_artifacts.push({
      package_name: receipt.package_name,
      package_id: receipt.package_id,
      artifact_key: receipt.key,
      payload,
    })
    var artifact_entries: List[types.RootEntry] = []

    for entry in metadata.entries {
      let planned: types.RootEntry = {
        package_name: receipt.package_name,
        package_id: receipt.package_id,
        artifact_key: receipt.key,
        path: entry.path,
        kind: entry.kind,
        mode: entry.mode,
        sha256: entry.sha256,
        target: entry.target,
      }

      for owner in entries {
        if owner.path == planned.path {
          return Err(types.PmError.PackageConflict(f"root path ${planned.path} is owned by both ${owner.package_name} and ${receipt.package_name}"))
        }

        if owner.path.starts_with(f"${planned.path}/") and planned.kind != types.Tree {
          return Err(types.PmError.PackageConflict(f"root non-directory ${planned.path} conflicts with ${owner.path} owned by ${owner.package_name}"))
        }

        if planned.path.starts_with(f"${owner.path}/") and owner.kind != types.Tree {
          return Err(types.PmError.PackageConflict(f"root non-directory ${owner.path} owned by ${owner.package_name} conflicts with ${planned.path}"))
        }
      }

      artifact_entries = artifact_entries.push(planned)
      entries = entries.push(planned)
    }

    if payload {
      root_verify_payload_entries(receipt, artifact_entries)?
    }
  }

  let ordered_artifacts = planned_artifacts |> sort-by .package_name
  let ordered_entries = entries |> sort-by .path
  let value: types.RootPlan = {
    format: "laputa-root-plan-1",
    target: types.Aarch64LinuxMusl,
    artifacts: ordered_artifacts,
    entries: ordered_entries,
    root_sha256: root_digest(types.Aarch64LinuxMusl, ordered_artifacts, ordered_entries),
  }
  root_validate_plan(value)?
  value
}

## Composes a verified root plan into a new output directory without mutating any completed root.
export proc compose(output: Path, plan: types.RootPlan, artifacts: List[types.ArtifactReceipt]) [fs, error] -> Result[types.RootReceipt] {
  let expected = preflight(artifacts)?

  if expected != plan {
    return Err(types.PmError.PackageContract("root plan does not match verified artifacts"))
  }

  if fs.exists(output)? {
    return Err(types.PmError.PackageConflict(f"immutable root ${output.display()} already exists"))
  }

  let temporary = fp"${output}.tmp"
  fs.remove(temporary, missing_ok: true)?
  defer fs.remove(temporary, missing_ok: true)?
  fs.mkdir(temporary)?
  let verified = root_verified_artifacts(artifacts)?
  var by_key: Map[types.ArtifactReceipt] = {}

  for artifact in verified {
    by_key[artifact.key] = artifact
  }

  for artifact in plan.artifacts {
    if artifact.payload {
      archive.tar_extract(fp"${by_key.get(artifact.artifact_key)?.artifact_dir}/payload.tar.gz", temporary)?
    }
  }

  let receipt = root_receipt_for_plan(plan)?
  fs.mkdir(root_receipt_path(temporary).parent)?
  fs.write(root_receipt_path(temporary), json.encode(root_receipt_dto(receipt))? + "\n")?
  verify(temporary, receipt)?
  fs.mkdir(output.parent)?
  fs.rename(temporary, output)?
  verify(output, receipt)?
  receipt
}

## Verifies the durable root receipt and every installed payload entry without consulting mutable package state.
export proc verify(output: Path, receipt: types.RootReceipt) [fs, error] {
  root_validate_receipt(receipt)?
  let stored = root_read_receipt(output)?

  if stored != receipt {
    return Err(types.PmError.PackageContract("root receipt does not match the completed root"))
  }

  for entry in receipt.entries {
    root_verify_entry_at(output, entry)?
  }
}
