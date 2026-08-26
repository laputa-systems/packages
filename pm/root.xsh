##! Deterministic immutable root plans composed only from verified artifact-store receipts.
use store as artifact_store
use types
use util

type ArtifactEntryDto = {path: Str, kind: Str, mode: Int, sha256: Str, target: Str}
# Legacy repository metadata supplied the exact payload inventory before it
# recorded package_kind.  Keep its required inventory typed, then handle that
# one omitted field at this decoder boundary; new recipe metadata is explicit.
type ArtifactMetadataDto = {name: Str, ver: Str, rel: Str, files: List[ArtifactEntryDto]}
type LegacyPackageDbMetadataDto = {
  name: Str,
  ver: Str,
  rel: Str,
  deps: List[Str],
  mkdeps_host: List[Str],
  mkdeps_target: List[Str],
  filetree: List[Record],
  nostrip: Bool,
  dir: Str,
  extract_install: Bool,
}
type LegacyPackageDbFile = {entry: types.ArtifactEntry, body: Bytes}
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

  if value.kind == types.file_kind_file() or value.kind == types.file_kind_binary() {
    if value.target != "" {
      return Err(types.PmError.PackageContract(f"file ${value.path} must not have a symlink target"))
    }

    root_require_sha256(value.sha256, f"file ${value.path} SHA-256")?
  } else if value.kind == types.file_kind_tree() {
    if value.sha256 != "" or value.target != "" {
      return Err(types.PmError.PackageContract(f"directory ${value.path} must not have a hash or target"))
    }
  } else if value.kind == types.file_kind_symlink() {
    if value.sha256 != "" {
      return Err(types.PmError.PackageContract(f"symlink ${value.path} must not have a file hash"))
    }

    root_validate_symlink_target(value.path, value.target)?
  }
}

pure root_legacy_package_db_path(receipt: types.ArtifactReceipt, name: Str) -> Path {
  fp"var/lib/xsh-pm/packages/${receipt.package_name}/${name}"
}

proc root_legacy_package_db_file(
  extracted: Path,
  receipt: types.ArtifactReceipt,
  name: Str,
) [fs, error] -> Result[LegacyPackageDbFile] {
  let root_handle = fs.open_root(extracted)?
  defer fs.close_root(root_handle)
  let rel = root_legacy_package_db_path(receipt, name)

  match fs.root_readlink(root_handle, rel) {
    Ok(_) => return Err(types.PmError.PackageContract(f"legacy package database ${rel.display()} must be a regular file"))
    Err(_) => {}
  }

  let metadata = fs.root_metadata(root_handle, rel)?

  if metadata.kind != "file" or metadata.mode % 4096 != 0o644 {
    return Err(types.PmError.PackageContract(f"legacy package database ${rel.display()} must be mode 0644 regular file"))
  }

  let body = fs.root_read(root_handle, rel)?
  {entry: {path: rel.display(), kind: types.file_kind_file(), mode: 0o644, sha256: body.sha256().hex(), target: ""}, body}
}

proc root_legacy_package_db_entries(
  receipt: types.ArtifactReceipt,
  sidecar: Record,
  dto: ArtifactMetadataDto,
  payload_entries: List[types.ArtifactEntry],
) [fs, error] -> Result[List[types.ArtifactEntry]] {
  let sandbox = fs.tempdir()?
  defer fs.close_root(sandbox)?
  let extracted = fp"${fs.root_path(sandbox)?}/payload"
  archive.tar_extract(fp"${receipt.artifact_dir}/payload.tar.gz", extracted)?
  let manifest_file = root_legacy_package_db_file(extracted, receipt, "manifest.json")?
  let etcsums_file = root_legacy_package_db_file(extracted, receipt, "etcsums.json")?
  let metadata_file = root_legacy_package_db_file(extracted, receipt, "metadata.json")?
  let sidecar_manifest = sidecar.get("manifest")?.require(List[Str])?
  let stored_manifest = json.decode(manifest_file.body.utf8()?)?.require(List[Str])?
  let expected_manifest = [entry.path for entry in payload_entries]

  if sidecar_manifest != expected_manifest or stored_manifest != sidecar_manifest {
    return Err(types.PmError.PackageContract(f"legacy package database manifest for ${receipt.package_name} does not match sidecar inventory"))
  }

  let stored_etcsums = json.decode(etcsums_file.body.utf8()?)?.require(List[types.EtcSum])?
  var expected_etcsums: List[types.EtcSum] = []

  for entry in payload_entries {
    if util.is_etc_file(fp"${entry.path}") and (entry.kind == types.file_kind_file() or entry.kind == types.file_kind_binary()) {
      expected_etcsums = expected_etcsums.push({path: entry.path, sha256: entry.sha256})
    }
  }

  if stored_etcsums != expected_etcsums {
    return Err(types.PmError.PackageContract(f"legacy package database etcsums for ${receipt.package_name} do not match sidecar payload hashes"))
  }

  let stored_metadata = json.decode(metadata_file.body.utf8()?)?.require(LegacyPackageDbMetadataDto)?
  let sidecar_deps = sidecar.get("deps")?.require(List[Str])?
  let sidecar_mkdeps_host = sidecar.get("mkdeps_host")?.require(List[Str])?
  let sidecar_mkdeps_target = sidecar.get("mkdeps_target")?.require(List[Str])?
  let sidecar_filetree = sidecar.get("filetree")?.require(List[Record])?

  if stored_metadata.name != dto.name or stored_metadata.ver != dto.ver or stored_metadata.rel != dto.rel or stored_metadata.deps != sidecar_deps or stored_metadata.mkdeps_host != sidecar_mkdeps_host or stored_metadata.mkdeps_target != sidecar_mkdeps_target or stored_metadata.filetree != sidecar_filetree or stored_metadata.nostrip or !stored_metadata.extract_install or stored_metadata.dir == "" {
    return Err(types.PmError.PackageContract(f"legacy package database metadata for ${receipt.package_name} does not match sidecar semantics"))
  }

  [manifest_file.entry, etcsums_file.entry, metadata_file.entry]
}

proc root_artifact_metadata(receipt: types.ArtifactReceipt) [fs, error] -> Result[DecodedArtifactMetadata] {
  let raw: Record = json.read(fp"${receipt.artifact_dir}/metadata.json")?
  let dto = raw.require(ArtifactMetadataDto)?
  let expected_id = util.package_id(dto.name, dto.ver, dto.rel)

  if dto.name != receipt.package_name or expected_id != receipt.package_id {
    return Err(types.PmError.PackageContract(f"artifact metadata does not match receipt ${receipt.package_id}"))
  }

  var kind = types.package_payload()

  if raw.has("package_kind") {
    let kind_text = raw.get("package_kind")?.require(Str)?
    kind = types.parse_package_kind(kind_text)?
  }
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

  if !raw.has("package_kind") {
    for entry in root_legacy_package_db_entries(receipt, raw, dto, entries)? {
      if seen.has(entry.path) {
        return Err(types.PmError.PackageContract(f"legacy package database entry ${entry.path} duplicates sidecar metadata for ${receipt.package_name}"))
      }

      seen[entry.path] = true
      entries = entries.push(entry)
    }
  }

  if kind == types.package_meta() and entries.len() != 0 {
    return Err(types.PmError.PackageContract(f"metapackage ${receipt.package_name} must have no payload entries"))
  }

  {kind, entries: entries |> sort-by .path}
}

proc root_verify_entry_at(root: Path, entry: types.RootEntry) [fs, error] -> Result[Unit] {
  let root_handle = fs.open_root(root)?
  defer fs.close_root(root_handle)
  let rel = fp"${entry.path}"

  # Root metadata follows the final path component. Inspect a declared symlink
  # first so a contained dangling or cyclic link remains a literal payload
  # entry instead of making receipt verification traverse it.
  if entry.kind == types.file_kind_symlink() {
    let target = fs.root_readlink(root_handle, rel)?

    if target.display() != entry.target {
      return Err(types.PmError.PackageContract(f"root symlink ${entry.path} does not match metadata"))
    }

    return Ok()
  }

  # Do not let an absent declaration escape as an unlabelled fs-root-stat
  # error: the caller needs the exact immutable inventory entry to diagnose a
  # malformed artifact, including from a parallel executor worker.
  if !fs.root_exists(root_handle, rel)? {
    return Err(types.PmError.PackageContract(f"root entry ${entry.path} is absent or unreadable"))
  }

  let meta = fs.root_metadata(root_handle, rel)?

  if entry.kind == types.file_kind_file() or entry.kind == types.file_kind_binary() {
    if meta.mode % 4096 != entry.mode {
      return Err(types.PmError.PackageContract(f"root entry ${entry.path} mode does not match metadata"))
    }

    if meta.kind != "file" or fs.root_read(root_handle, rel)?.sha256().hex() != entry.sha256 {
      return Err(types.PmError.PackageContract(f"root file ${entry.path} does not match metadata"))
    }
  } else if entry.kind == types.file_kind_tree() {
    if meta.kind != "dir" or meta.mode % 4096 != entry.mode {
      return Err(types.PmError.PackageContract(f"root directory ${entry.path} does not match metadata"))
    }
  }

  return Ok()
}

# Directories are structural paths, not exclusive file ownership. Identical declarations
# coalesce to the first canonical artifact owner; every artifact is still verified against
# its own directory metadata before composition. Files and symlinks remain exclusive.
pure root_same_directory_metadata(left: types.RootEntry, right: types.RootEntry) -> Bool {
  left.kind == types.file_kind_tree()
    and right.kind == types.file_kind_tree()
    and left.mode == right.mode
    and left.sha256 == right.sha256
    and left.target == right.target
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
    # Keep the immutable receipt owner and exact metadata path at this
    # archive boundary.  A raw filesystem error otherwise loses the artifact
    # that supplied the malformed inventory, especially when this runs inside
    # a parallel executor worker.
    match root_verify_entry_at(extracted, entry) {
      Ok(_) => {}
      Err(problem) => {
        return Err(types.PmError.PackageContract(f"artifact ${receipt.package_name} payload entry ${entry.path} failed verification: ${problem.message}"))
      }
    }
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

  if value.target != types.target_aarch64() {
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

# An artifact archive is never extracted over the assembled root.  Preflight
# has already checked its complete payload inventory; apply only that plan's
# canonical entries so the archive implementation cannot overwrite a sibling
# artifact's path after the conflict check has passed.
proc root_materialize_entry(source_root: Path, output: Path, entry: types.RootEntry) [fs, error] {
  let source = fp"${source_root}/${entry.path}"
  let destination = fp"${output}/${entry.path}"

  if entry.kind == types.file_kind_tree() {
    if fs.exists(destination)? {
      root_verify_entry_at(output, entry)?
      return
    }

    fs.mkdir(destination, parents: true)?
    fs.chmod(destination, entry.mode)?
    root_verify_entry_at(output, entry)?
    return
  }

  if fs.exists(destination)? {
    return Err(types.PmError.PackageConflict(f"root path ${entry.path} already exists while applying ${entry.package_name}"))
  }

  fs.mkdir(destination.parent, parents: true)?

  if entry.kind == types.file_kind_file() or entry.kind == types.file_kind_binary() {
    fs.copy(source, destination)?
    fs.chmod(destination, entry.mode)?
  } else if entry.kind == types.file_kind_symlink() {
    fs.symlink(fp"${entry.target}", destination)?
  }

  root_verify_entry_at(output, entry)?
}

proc root_materialize_artifact(
  output: Path,
  receipt: types.ArtifactReceipt,
  entries: List[types.RootEntry],
) [fs, error] {
  let sandbox = fs.tempdir()?
  defer fs.close_root(sandbox)?
  let extracted = fp"${fs.root_path(sandbox)?}/payload"
  archive.tar_extract(fp"${receipt.artifact_dir}/payload.tar.gz", extracted)?

  for entry in entries {
    root_materialize_entry(extracted, output, entry)?
  }
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
    let payload = metadata.kind != types.package_meta()
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
          if root_same_directory_metadata(owner, planned) {
            continue
          }

          if owner.kind == types.file_kind_tree() and planned.kind == types.file_kind_tree() {
            return Err(types.PmError.PackageConflict(f"root directory ${planned.path} has incompatible metadata from ${owner.package_name} and ${receipt.package_name}"))
          }

          return Err(types.PmError.PackageConflict(f"root path ${planned.path} is owned by both ${owner.package_name} and ${receipt.package_name}"))
        }

        if owner.path.starts_with(f"${planned.path}/") and planned.kind != types.file_kind_tree() {
          return Err(types.PmError.PackageConflict(f"root non-directory ${planned.path} conflicts with ${owner.path} owned by ${owner.package_name}"))
        }

        if planned.path.starts_with(f"${owner.path}/") and owner.kind != types.file_kind_tree() {
          return Err(types.PmError.PackageConflict(f"root non-directory ${owner.path} owned by ${owner.package_name} conflicts with ${planned.path}"))
        }
      }

      artifact_entries = artifact_entries.push(planned)

      var coalesced = false

      for owner in entries {
        if owner.path == planned.path and root_same_directory_metadata(owner, planned) {
          coalesced = true
          break
        }
      }

      if ! coalesced {
        entries = entries.push(planned)
      }
    }

    if payload {
      root_verify_payload_entries(receipt, artifact_entries)?
    }
  }

  let ordered_artifacts = planned_artifacts |> sort-by .package_name
  let ordered_entries = entries |> sort-by .path
  let value: types.RootPlan = {
    format: "laputa-root-plan-1",
    target: types.target_aarch64(),
    artifacts: ordered_artifacts,
    entries: ordered_entries,
    root_sha256: root_digest(types.target_aarch64(), ordered_artifacts, ordered_entries),
  }
  root_validate_plan(value)?
  value
}

## Composes package artifacts into a verified root plan. The explicit `compose_artifacts` spelling
## avoids XSH's shared-module export collision with the public `generation.compose` boundary.
export proc compose_artifacts(output: Path, plan: types.RootPlan, artifacts: List[types.ArtifactReceipt]) [fs, error] -> Result[types.RootReceipt] {
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
      let entries = [entry for entry in plan.entries if entry.artifact_key == artifact.artifact_key]
      root_materialize_artifact(temporary, by_key.get(artifact.artifact_key)?, entries)?
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
