##! PM repo operations and shared package-manager policy.
use build as pm_build
use buildroot
use catalog
use extensions
use fingerprint
use graph
use local
use plan as build_plan
use policy
use proof as pm_proof
use remote
use store
use types
use util

type RepoArtifactMetadataDto = {name: Str, ver: Str, rel: Str, package_kind: Str?}
type RepoIndexMerge = {index: List[types.RemotePackage], already_published: Bool}
type RepoPublishStage = {publication: types.RepoPublication, entry: types.RemotePackage, metadata: Path}

## Exported PM declaration `stage_built_package`.
export proc stage_built_package(
  repo_dir: Path,
  upload_ctx: types.PmContext,
  index: List[types.RemotePackage],
  item: types.BuiltPackage,
) [fs, process, env, error] -> Result[List[types.RemotePackage]] {
  let arch = util.machine_arch()?
  let tarball_rel = util.remote_binary_rel(arch, item.pkg.name, item.pkg.ver, item.pkg.rel)
  let metadata_rel = util.remote_metadata_rel(arch, item.pkg.name, item.pkg.ver, item.pkg.rel)
  let dest = fp"${repo_dir}/${tarball_rel}"
  let metadata_dest = fp"${repo_dir}/${metadata_rel}"
  fs.mkdir(dest.parent)?
  fs.copy(item.tarball, dest, overwrite: true)?
  local.write_package_metadata(metadata_dest, arch, item)?
  let tarball_metadata = fs.metadata(item.tarball)?

  let entry = remote.remote_entry_for(
    arch,
    item.pkg,
    tarball_rel.display(),
    hash.sha256(item.tarball)?.hex(),
    tarball_metadata.size,
    metadata_rel.display(),
    "",
    false,
  )

  let updated = remote.upsert_remote_package(index, entry)?
  extensions.run_lifecycle_hooks("post-upload", item.pkg.name, upload_ctx, "")?
  print --flush ${item.pkg.name} util.version_id(item.pkg.ver, item.pkg.rel) "stage:" "done"
  updated
}

proc order_repo_build_packages(
  root: Path,
  packages: List[types.Package],
  index: List[types.RemotePackage],
) [fs, env, error] -> Result[List[types.Package]] {
  let arch = util.machine_arch()?
  let remote_names = remote.selected_snapshot_names(index, arch)
  var local_names: Map[Bool] = {}
  var available_names = remote_names

  for pkg in packages {
    local_names[pkg.name] = true
  }

  for pkg in packages {
    for dependency in pkg.deps {
      if ! local_names.get(dependency, false) {
        if dependency not in remote_names and ! fs.exists(util.package_db_path(root, dependency))? {
          return Err(types.PmError.MissingDependency(f"${pkg.name} depends on missing ${dependency}"))
        }

        available_names = available_names.push(dependency)
      }
    }

    for dependency in pkg.mkdeps_host.extend(pkg.mkdeps_target) {
      if ! local_names.get(dependency, false) {
        available_names = available_names.push(dependency)
      }
    }
  }

  let local_catalog = catalog.from_packages(root, packages, available_names)?
  let value = remote.catalog_with_selected_snapshot(local_catalog, index, arch)?
  let edges = graph.edges(value, policy.aarch64_docker())?
  let runtime_edges = [edge for edge in edges if edge.kind == types.Runtime]
  let levels = graph.topological_levels(catalog.package_names(value), runtime_edges)?
  let by_name = catalog.package_map(value)
  var ordered: List[types.Package] = []

  for level in levels {
    for name in level {
      if by_name.has(name) {
        let pkg: types.Package = by_name.get(name)?
        ordered = ordered.push(pkg)
      }
    }
  }

  ordered
}

pure repo_fingerprint_target(arch: Str) -> types.Target {
  if arch == "aarch64" {
    return types.Aarch64LinuxMusl
  }

  types.TargetReserved
}

proc repo_pm_source_root() [fs, env, error] -> Result[Path] {
  for entry in (env.get("XSH_MODULE_PATH") ?? "").split(":") {
    let candidate = fp"${entry}"

    if fs.exists(fp"${candidate}/pm.xsh")? and fs.exists(fp"${candidate}/pm")? {
      return path.absolute(candidate)?
    }
  }

  for candidate in [p".", p"laputa", /usr/lib/pm] {
    if fs.exists(fp"${candidate}/pm.xsh")? and fs.exists(fp"${candidate}/pm")? {
      return path.absolute(candidate)?
    }
  }

  return Err(types.PmError.PackageContract("cannot locate PM source root for proof receipt verification"))
}

proc verify_proof_receipt(out: Path, pkg: types.Package, tarball: Path) [fs, env, error] {
  let receipt = util.proof_receipt_path(out, pkg)

  if ! fs.exists(receipt)? {
    return Err(
      types.PmError.PackageTarball(f"${pkg.name} has no successful proof receipt; build and prove it before upload"),
    )
  }

  let metadata: Record = json.read(receipt)?
  let expected: Str = metadata.get("tarball_sha256")?
  let actual = hash.sha256(tarball)?.hex()

  if expected != actual {
    return Err(types.PmError.PackageTarball(f"${pkg.name} proof receipt does not match the package tarball"))
  }

  if metadata.has("build_input") {
    let recorded: Str = metadata.get("build_input")?
    let pm_root = repo_pm_source_root()?
    let current = fingerprint.package_build_input(pm_root, pkg, repo_fingerprint_target(util.machine_arch()?))?

    if recorded != current {
      return Err(types.PmError.PackageTarball(f"${pkg.name} proof receipt build input is stale; rebuild before upload"))
    }
  }

  if metadata.has("proof_input") {
    let recorded: Str = metadata.get("proof_input")?
    let current = fingerprint.package_proof_input(repo_pm_source_root()?, pkg)?

    if recorded != current {
      return Err(types.PmError.PackageTarball(f"${pkg.name} proof receipt input is stale; re-prove before upload"))
    }
  }
}

proc repo_expected_executor_sha256(value: types.BuildPlan) [error] -> Result[Str] {
  build_plan.executor_fingerprint(value.executor)?
}

proc repo_verify_node_receipt(
  value: types.BuildPlan,
  node: types.PlanNode,
  receipt: types.ArtifactReceipt,
) [error] {
  let executor_sha256 = repo_expected_executor_sha256(value)?
  let dependency_keys = [dependency.artifact_key for dependency in node.dependencies]
  let runtime_dependency_keys = [dependency.artifact_key for dependency in node.dependencies if dependency.kind == types.Runtime]

  if receipt.key != node.artifact_key or receipt.target != value.target or receipt.package_name != node.name or receipt.package_id != node.package_id or receipt.recipe_sha256 != node.recipe_sha256 or receipt.executor_sha256 != executor_sha256 or receipt.dependency_keys != dependency_keys or receipt.runtime_dependency_keys != runtime_dependency_keys {
    return Err(types.PmError.PackageContract(f"artifact receipt ${node.artifact_key} does not match BuildPlan node ${node.package_id}"))
  }

  if types.plan_action_is_build(node.action) {
    if receipt.origin != types.Built {
      return Err(types.PmError.PackageContract(f"BuildPlan build node ${node.package_id} is not a locally proved artifact"))
    }
  } else if receipt.origin != types.Remote {
    return Err(types.PmError.PackageContract(f"BuildPlan remote node ${node.package_id} is not a verified imported artifact"))
  }
}

proc repo_package_kind(receipt: types.ArtifactReceipt, node: types.PlanNode) [fs, error] -> Result[types.PackageKind] {
  let metadata = fp"${receipt.artifact_dir}/metadata.json"
  let core = json.read(metadata)?.require(RepoArtifactMetadataDto)?

  if core.name != node.name or core.ver != node.ver or core.rel != node.rel {
    return Err(types.PmError.PackageContract(f"artifact metadata ${metadata.display()} does not match ${node.package_id}"))
  }

  let package_kind = core.package_kind ?? ""

  if package_kind != "" {
    return types.parse_package_kind(package_kind)
  }

  # Package-kind fields appeared after legacy remote metadata. Their omitted form was payload.
  types.Payload
}

proc repo_verified_proof_path(
  store_root: Path,
  node: types.PlanNode,
  receipt: types.ArtifactReceipt,
) [fs, error] -> Result[Path] {
  let payload = fp"${receipt.artifact_dir}/payload.tar.gz"
  let primary = fp"${receipt.artifact_dir}/proof.json"

  if receipt.origin == types.Remote {
    # import_remote already hashes and verifies its opaque remote proof object through the Store receipt.
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
    deps: [dependency.name for dependency in node.dependencies if dependency.kind == types.Runtime],
    mkdeps_host: [dependency.name for dependency in node.dependencies if dependency.kind == types.BuildHost],
    mkdeps_target: [dependency.name for dependency in node.dependencies if dependency.kind == types.BuildTarget],
    sha256: if value.kind == types.Meta { "" } else { hash.sha256(value.payload)?.hex() },
    size: if value.kind == types.Meta { 0 } else { fs.metadata(value.payload)?.size },
    tarball: if value.kind == types.Meta { "" } else { payload_rel.display() },
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
    metapackage: value.kind == types.Meta,
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
  if snapshot.format != "laputa-repo-snapshot-1" or snapshot.target != types.Aarch64LinuxMusl {
    return Err(types.PmError.PackageContract("unsupported repository snapshot"))
  }

  if remote_repo == "" {
    return Err(types.PmError.RemoteRepo("repository publication needs a remote repository"))
  }

  if ! util.is_file_url(remote_repo) and token.trim() == "" {
    return Err(types.PmError.Auth("repository publication needs a token for network remotes"))
  }

  fs.mkdir(work)?
  var stages: List[RepoPublishStage] = []

  for publication in snapshot.packages {
    let verified = store.verify_receipt(publication.receipt)?

    if verified != publication.receipt {
      return Err(types.PmError.PackageContract(f"repository snapshot receipt changed for ${publication.node.package_id}"))
    }

    if publication.receipt.origin == types.Built {
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

## Exported PM declaration `upload_set_repo`.
export proc upload_set_repo(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 3 {
    return Err(types.PmError.Usage("usage: pm upload-set REPO_DIR PKGDIR..."))
  }

  let repo_dir = path.absolute(fp"${argv[1]}")?
  let build_root = fp"${repo_dir}/.set-build-root"
  let work = fp"${repo_dir}/.work"
  let out = fp"${repo_dir}/.out"
  let upload_ctx: types.PmContext = {command: "upload", root: build_root, work, out}
  var raw_args = []
  var build_i = 2

  while build_i < argv.len() {
    raw_args = raw_args.push(argv[build_i])
    build_i += 1
  }

  fs.mkdir(work)?
  fs.mkdir(out)?
  let lock = fs.lock(fp"${work}/pm.lock")?
  defer fs.unlock(lock)?
  let packages = local.load_package_dirs(util.paths_from_args(raw_args)?)?

  for pkg in packages {
    upload_package(upload_ctx, pkg)?
  }
}

## Exported PM declaration `build_repo`.
export proc build_repo(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 3 {
    return Err(types.PmError.Usage("usage: pm build REPO_DIR PKGDIR..."))
  }

  let repo_dir = path.absolute(fp"${argv[1]}")?
  let build_work = fp"${repo_dir}/.work"
  let build_out = fp"${repo_dir}/.out"
  let build_root = fp"${repo_dir}/.root"
  let ctx: types.PmContext = {command: "build", root: build_root, work: build_work, out: build_out}
  let upload_ctx: types.PmContext = {...ctx, command: "upload"}
  fs.mkdir(repo_dir)?
  var raw_args = []
  var build_i = 2

  while build_i < argv.len() {
    raw_args = raw_args.push(argv[build_i])
    build_i += 1
  }

  let index_path = fp"${repo_dir}/index.json"
  var index = []

  if fs.exists(index_path)? {
    index = remote.load_remote_index_from(index_path)?
  }

  let packages = local.load_package_dirs(util.paths_from_args(raw_args)?)?
  let local_names = buildroot.local_package_names(packages)
  buildroot.install_remote_dependency_set(
    ctx,
    buildroot.missing_dependency_names(build_root, packages, true, local_names)?,
  )?
  let ordered = order_repo_build_packages(build_root, packages, index)?
  let built = pm_build.build_packages(ctx, ordered)?

  for item in built {
    index = stage_built_package(repo_dir, upload_ctx, index, item)?
  }

  json.write(index_path, index)?
}

## Exported PM declaration `upload_package`.
export proc upload_package(ctx: types.PmContext, pkg: types.Package) [fs, net, process, env, time, error] {
  let repo_urls = remote.require_repo_url()?
  let token = remote.require_auth_token(ctx.root)?
  extensions.run_lifecycle_hooks("pre-upload", pkg.name, ctx, "")?
  let repo = repo_urls.repo
  let arch = util.machine_arch()?
  var index = remote.load_remote_index_from_repo(repo, ctx.out)?

  if pkg.kind == types.Meta {
    let entry = remote.remote_entry_for(arch, pkg, "", "", 0, "", "", true)
    index = remote.upsert_remote_package(index, entry)?
    remote.write_remote_index_to_repo(repo, ctx.work, ctx.out, index, token)?
    extensions.run_lifecycle_hooks("post-upload", pkg.name, ctx, "metapackage")?
    print ${pkg.name} util.version_id(pkg.ver, pkg.rel) "staged"
    return
  }

  let tarball = fp"${ctx.out}/${util.remote_tarball_name(pkg.name, pkg.ver, pkg.rel)}"

  if ! fs.exists(tarball)? {
    return Err(types.PmError.PackageTarball(f"${tarball.display()} is missing; build before upload"))
  }

  verify_proof_receipt(ctx.out, pkg, tarball)?
  let tarball_rel = util.remote_binary_rel(arch, pkg.name, pkg.ver, pkg.rel)
  let tarball_metadata = fs.metadata(tarball)?

  if tarball_metadata.size > 52428800 {
    remote.upload_large_repo_file(repo, tarball_rel, tarball, token, ctx.work)?
  } else {
    remote.upload_repo_file(repo, tarball_rel, tarball, token, ctx.work)?
  }

  let id = util.package_id(pkg.name, pkg.ver, pkg.rel)
  let metadata_stage = fp"${ctx.work}/${id}-metadata"
  fs.remove(metadata_stage, missing_ok: true)?
  fs.mkdir(metadata_stage)?
  archive.tar_extract(tarball, metadata_stage, 0, "auto", true)?
  let built = local.load_built_package_from_dest(pkg, id, tarball, metadata_stage)?
  let metadata_rel = util.remote_metadata_rel(arch, pkg.name, pkg.ver, pkg.rel)
  let metadata_path = fp"${ctx.out}/${metadata_rel}"
  local.write_package_metadata(metadata_path, arch, built)?
  remote.upload_repo_file(repo, metadata_rel, metadata_path, token, ctx.work)?
  let uploaded_source = remote.upload_package_source(repo, ctx.work, ctx.out, pkg, token)?

  let entry = remote.remote_entry_for(
    arch,
    pkg,
    tarball_rel.display(),
    hash.sha256(tarball)?.hex(),
    tarball_metadata.size,
    metadata_rel.display(),
    uploaded_source.sha256,
    false,
  )

  index = remote.upsert_remote_package(index, entry)?
  remote.write_remote_index_to_repo(repo, ctx.work, ctx.out, index, token)?
  extensions.run_lifecycle_hooks("post-upload", pkg.name, ctx, "")?
  print ${pkg.name} util.version_id(pkg.ver, pkg.rel) "uploaded"

  if uploaded_source.rel != "" {
    print ${pkg.name} source uploaded
  }
}

## Exported PM declaration `upload_repo_export_file`.
export proc upload_repo_export_file(repo: Str, rel: Path, source: Path, token: Str, work: Path) [fs, net, time, error] {
  let metadata = fs.metadata(source)?

  if metadata.size > 52428800 {
    remote.upload_large_repo_file(repo, rel, source, token, work)?
  } else {
    remote.upload_repo_file(repo, rel, source, token, work)?
  }
}

proc export_entry_with_local_source(
  repo_dir: Path,
  entry: types.RemotePackage,
) [fs, error] -> Result[types.RemotePackage] {
  let source = fp"${repo_dir}/.out/source-mirrors/${util.package_id(entry.name, entry.ver, entry.rel)}-${entry.arch}.tar.bz2"

  if ! fs.exists(source)? {
    return entry
  }

  {...entry, source_sha256: hash.sha256(source)?.hex()}
}

proc remote_export_entry_same(remote_index: List[types.RemotePackage], entry: types.RemotePackage) [] -> Bool {
  for rpkg in remote_index {
    if rpkg.arch == entry.arch and rpkg.name == entry.name {
      return rpkg.ver == entry.ver and rpkg.rel == entry.rel and rpkg.deps == entry.deps and rpkg.mkdeps_host == entry.mkdeps_host and (rpkg.mkdeps_target.len() == 0 or rpkg.mkdeps_target == entry.mkdeps_target) and rpkg.sha256 == entry.sha256 and rpkg.size == entry.size and rpkg.tarball == entry.tarball and rpkg.metadata == entry.metadata and rpkg.source_sha256 == entry.source_sha256 and rpkg.metapackage == entry.metapackage
    }
  }

  false
}

## Exported PM declaration `upload_repo_export`.
export proc upload_repo_export(argv: List[Str]) [fs, net, process, env, time, error] {
  if argv.len() < 2 {
    return Err(types.PmError.Usage("usage: pm upload-repo-export REPO_DIR"))
  }

  let repo_dir = path.absolute(fp"${argv[1]}")?
  let index_path = fp"${repo_dir}/index.json"
  let work = fp"${repo_dir}/.upload-work"
  let out = fp"${repo_dir}/.upload-out"
  let root = fp"${repo_dir}/.upload-root"
  let repo_urls = remote.require_repo_url()?
  let token = remote.require_auth_token(root)?
  let repo = repo_urls.repo
  print --flush "repo-export" "loading" "remote index"
  var remote_index = remote.load_remote_index_from_repo(repo, out)?
  let export_index = remote.load_remote_index_from(index_path)?
  fs.mkdir(work)?
  fs.mkdir(out)?
  var pending = []

  for staged_entry in export_index {
    let entry = export_entry_with_local_source(repo_dir, staged_entry)?

    if remote_export_entry_same(remote_index, entry) {
      print --flush f"repo-export" ${entry.arch} ${entry.name} util.version_id(entry.ver, entry.rel) "already-exported"
    } else {
      pending = pending.push(entry)
    }
  }

  let uploaded_entries = pending
    |> par-map --jobs=4 { |entry|
      var uploaded = entry
      print --flush f"repo-export" ${entry.arch} ${entry.name} util.version_id(entry.ver, entry.rel) "uploading"

      if ! entry.metapackage {
        if entry.tarball == "" {
          return Err(
            types.PmError.PackageTarball(f"${entry.name} ${util.version_id(entry.ver, entry.rel)} has no tarball"),
          )
        }

        let tarball_rel = util.ensure_relative_path(fp"${entry.tarball}", "remote tarball")?
        let tarball = fp"${repo_dir}/${tarball_rel.display()}"

        if ! fs.exists(tarball)? {
          return Err(types.PmError.PackageTarball(f"${tarball.display()} is missing"))
        }

        let tarball_metadata = fs.metadata(tarball)?
        print --flush f"repo-export" ${entry.arch} ${entry.name} "uploading" "tarball" f"${tarball_metadata.size} bytes"
        upload_repo_export_file(repo, tarball_rel, tarball, token, work)?
        uploaded = {...uploaded, sha256: hash.sha256(tarball)?.hex(), size: tarball_metadata.size}

        if entry.metadata != "" {
          let metadata_rel = util.ensure_relative_path(fp"${entry.metadata}", "remote metadata")?
          let metadata = fp"${repo_dir}/${metadata_rel.display()}"

          if ! fs.exists(metadata)? {
            return Err(types.PmError.PackageTarball(f"${metadata.display()} is missing"))
          }

          let metadata_size = fs.metadata(metadata)?.size
          print --flush f"repo-export" ${entry.arch} ${entry.name} "uploading" "metadata" f"${metadata_size} bytes"
          upload_repo_export_file(repo, metadata_rel, metadata, token, work)?
        }
      }

      let source = fp"${repo_dir}/.out/source-mirrors/${util.package_id(entry.name, entry.ver, entry.rel)}-${entry.arch}.tar.bz2"

      if fs.exists(source)? {
        let source_rel = util.remote_source_rel_for_arch(entry.arch, entry.name, entry.ver, entry.rel)
        let source_size = fs.metadata(source)?.size
        print --flush f"repo-export" ${entry.arch} ${entry.name} "uploading" "source" f"${source_size} bytes"
        upload_repo_export_file(repo, source_rel, source, token, work)?
        uploaded = {...uploaded, source_sha256: hash.sha256(source)?.hex()}
      }

      uploaded
    }

  for uploaded in uploaded_entries {
    remote_index = remote.upsert_remote_package(remote_index, uploaded)?
    print --flush ${uploaded.arch} ${uploaded.name} util.version_id(uploaded.ver, uploaded.rel) "exported"
  }

  print --flush "repo-export" "writing" "remote index"
  remote.write_remote_index_to_repo(repo, work, out, remote_index, token)?
  print --flush "repo" export uploaded
}
