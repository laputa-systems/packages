##! Stable typed package-manager domains and shared PM context types.
## The package-manager error family is returned by PM operations.
export error PmError = Usage(message: Str) : Usage | MissingDependency(message: Str) : Dependency | DependencyCycle(message: Str) : Dependency | ExtensionFailed(message: Str) | LifecycleHook(message: Str) | PackageTarball(message: Str) : NotFound | PackageConflict(message: Str) : Conflict | DirtyFilesystem(message: Str) : Conflict | PackageContract(message: Str) : InvalidData | DependentPackage(message: Str) : Dependency | PackageNotInstalled(message: Str) : NotFound | RemoteRepo(message: Str) : Remote | Auth(message: Str) : PermissionDenied | RemoteFetch(message: Str) : Remote | RemoteUpload(message: Str) : Remote | RemoteIndex(message: Str) : Remote | RemotePackage(message: Str) : NotFound | SourceDestination(message: Str) : InvalidData | SourceName(message: Str) : InvalidData | DownloadFailed(message: Str) : Remote | DownloadTool(message: Str) : NotFound | SourceNotFound(message: Str) : NotFound | SourceChecksum(message: Str) : InvalidData | ChecksumField(message: Str) : InvalidData

## The sole supported package build target.
export type Target = Aarch64LinuxMusl | TargetReserved

## The package payload model selected explicitly by every recipe.
export type PackageKind = Payload | Meta

## The semantic reason one package depends on another.
export type DependencyKind = Runtime | BuildHost | BuildTarget | Bootstrap

## The source staging strategy selected by a recipe source record.
export type SourceKind = Auto | Archive | Zip | Cpio | SourceFile | Directory | Git

## The expected on-disk kind for a declared package output path.
export type FileKind = File | Binary | Symlink | Tree

## The selected execution strategy for one durable build-plan node.
export type PlanAction = Build(Str) | ReuseRemote(Str)

## The immutable origin of one package artifact in the local store.
export type ArtifactOrigin = Built | Remote

# The pinned published XSH runner exposes imported tagged-union constructors as
# global tags, not module-record methods.  Keep PM callers on these typed
# accessors so a plan behaves the same under the release runner and the newer
# host checker without relying on a shared global tag spelling.
## Return the sole build target without a qualified union-tag expression.
export pure target_aarch64() -> Target {
  return Aarch64LinuxMusl
}

## Return the internal unsupported-target sentinel.
export pure target_reserved() -> Target {
  return TargetReserved
}

## Return the package kind that owns a payload.
export pure package_payload() -> PackageKind {
  return Payload
}

## Return the package kind that owns no payload.
export pure package_meta() -> PackageKind {
  return Meta
}

## Return the runtime dependency edge kind.
export pure dependency_runtime() -> DependencyKind {
  return Runtime
}

## Return the host build dependency edge kind.
export pure dependency_build_host() -> DependencyKind {
  return BuildHost
}

## Return the target build dependency edge kind.
export pure dependency_build_target() -> DependencyKind {
  return BuildTarget
}

## Return the policy-provided bootstrap edge kind.
export pure dependency_bootstrap() -> DependencyKind {
  return Bootstrap
}

## Return automatic source-kind inference.
export pure source_auto() -> SourceKind {
  return Auto
}

## Return archive source staging.
export pure source_archive() -> SourceKind {
  return Archive
}

## Return ZIP source staging.
export pure source_zip() -> SourceKind {
  return Zip
}

## Return CPIO source staging.
export pure source_cpio() -> SourceKind {
  return Cpio
}

## Return a single-file source staging kind.
export pure source_file() -> SourceKind {
  return SourceFile
}

## Return a directory source staging kind.
export pure source_directory() -> SourceKind {
  return Directory
}

## Return Git source staging.
export pure source_git() -> SourceKind {
  return Git
}

## Return the regular-file metadata kind.
export pure file_kind_file() -> FileKind {
  return File
}

## Return the ELF/binary metadata kind.
export pure file_kind_binary() -> FileKind {
  return Binary
}

## Return the symlink metadata kind.
export pure file_kind_symlink() -> FileKind {
  return Symlink
}

## Return the directory-tree metadata kind.
export pure file_kind_tree() -> FileKind {
  return Tree
}

## Construct the local-build action with its durable reason.
export pure plan_action_build(reason: Str) -> PlanAction {
  return Build(reason)
}

## Construct the remote-reuse action with its durable reason.
export pure plan_action_reuse_remote(reason: Str) -> PlanAction {
  return ReuseRemote(reason)
}

## Return the local-build artifact origin.
export pure artifact_origin_built() -> ArtifactOrigin {
  return Built
}

## Return the imported-remote artifact origin.
export pure artifact_origin_remote() -> ArtifactOrigin {
  return Remote
}

## Renders the supported target as its stable external text form.
export pure target_text(target: Target) -> Str {
  match target {
    Aarch64LinuxMusl => return "aarch64-linux-musl"
    TargetReserved => return ""
  }
}

## Decodes the one supported target from a public text boundary.
export pure parse_target(raw: Str) -> Result[Target] {
  match raw {
    "aarch64-linux-musl" => return Aarch64LinuxMusl
    "aarch64" => return Aarch64LinuxMusl
    "arm64" => return Aarch64LinuxMusl
    "arm64-linux-musl" => return Aarch64LinuxMusl
    _ => return Err(PmError.PackageContract(f"unsupported target ${raw}"))
  }
}

## Renders one build-plan action for its JSON-facing data-transfer record.
export pure plan_action_text(action: PlanAction) -> Str {
  match action {
    Build(_) => return "build"
    ReuseRemote(_) => return "reuse-remote"
  }
}

## Returns the explanation carried by one build-plan action.
export pure plan_action_reason(action: PlanAction) -> Str {
  match action {
    Build(reason) => return reason
    ReuseRemote(reason) => return reason
  }
}

## Returns whether a plan action executes a local build.
export pure plan_action_is_build(action: PlanAction) -> Bool {
  match action {
    Build(_) => return true
    ReuseRemote(_) => return false
  }
}

## Decodes one build-plan action at a JSON boundary.
export pure parse_plan_action(raw: Str, reason: Str) -> Result[PlanAction] {
  match raw {
    "build" => return Build(reason)
    "reuse-remote" => return ReuseRemote(reason)
    _ => return Err(PmError.PackageContract(f"invalid build-plan action ${raw}"))
  }
}

## Renders an artifact origin for its JSON-facing receipt record.
export pure artifact_origin_text(origin: ArtifactOrigin) -> Str {
  match origin {
    Built => return "built"
    Remote => return "remote"
  }
}

## Decodes an artifact origin at the durable receipt boundary.
export pure parse_artifact_origin(raw: Str) -> Result[ArtifactOrigin] {
  match raw {
    "built" => return Built
    "remote" => return Remote
    _ => return Err(PmError.PackageContract(f"invalid artifact origin ${raw}"))
  }
}

## Renders a package kind for recipe and repository metadata.
export pure package_kind_text(kind: PackageKind) -> Str {
  match kind {
    Payload => return "payload"
    Meta => return "meta"
  }
}

## Decodes a package kind at the recipe metadata boundary.
export pure parse_package_kind(raw: Str) -> Result[PackageKind] {
  match raw {
    "payload" => return Payload
    "meta" => return Meta
    _ => return Err(PmError.PackageContract(f"invalid package kind ${raw}"))
  }
}

## Renders a dependency kind for serialized graph records.
export pure dependency_kind_text(kind: DependencyKind) -> Str {
  match kind {
    Runtime => return "runtime"
    BuildHost => return "build-host"
    BuildTarget => return "build-target"
    Bootstrap => return "bootstrap"
  }
}

## Decodes a dependency kind at a serialized graph boundary.
export pure parse_dependency_kind(raw: Str) -> Result[DependencyKind] {
  match raw {
    "runtime" => return Runtime
    "build-host" => return BuildHost
    "build-target" => return BuildTarget
    "bootstrap" => return Bootstrap
    _ => return Err(PmError.PackageContract(f"invalid dependency kind ${raw}"))
  }
}

## Renders a source kind for legacy recipe metadata and source staging.
export pure source_kind_text(kind: SourceKind) -> Str {
  match kind {
    Auto => return "auto"
    Archive => return "archive"
    Zip => return "zip"
    Cpio => return "cpio"
    SourceFile => return "file"
    Directory => return "directory"
    Git => return "git"
  }
}

## Decodes a source kind before a recipe enters typed PM code.
export pure parse_source_kind(raw: Str) -> Result[SourceKind] {
  match raw {
    "auto" => return Auto
    "archive" => return Archive
    "zip" => return Zip
    "cpio" => return Cpio
    "file" => return SourceFile
    "directory" => return Directory
    "git" => return Git
    _ => return Err(PmError.PackageContract(f"invalid upstream source kind ${raw}"))
  }
}

## Renders a file kind for legacy package metadata and output validation.
export pure file_kind_text(kind: FileKind) -> Str {
  match kind {
    File => return "file"
    Binary => return "binary"
    Symlink => return "symlink"
    Tree => return "tree"
  }
}

## Decodes a file kind before a recipe enters typed PM code.
export pure parse_file_kind(raw: Str) -> Result[FileKind] {
  match raw {
    "file" => return File
    "binary" => return Binary
    "symlink" => return Symlink
    "tree" => return Tree
    _ => return Err(PmError.PackageContract(f"invalid filetree kind ${raw}"))
  }
}

## A declared package output path and its typed expected kind.
export type FileTreeEntry = {path: Path, kind: FileKind}

## A source checksum keyed by target architecture.
export type SourceChecksum = {arch: Str, sha256: Str}

## An upstream source and the architectures it serves.
export type UpstreamSource = {source: Path, kind: SourceKind, architectures: List[Str], checksums: List[SourceChecksum]}

## A stable package tuple used by plans and artifact identities.
export type PackageId = {name: Str, ver: Str, rel: Str}

## A typed directional dependency in a resolved package graph.
export type DependencyEdge = {from: Str, to: Str, kind: DependencyKind}

## A policy-defined dependency supplied by the bootstrap environment rather than a locally ordered package build.
export type BootstrapSeedRule = {package: Str, dependency: Str, native_only: Bool, reason: Str}

## A normalized package definition loaded by the package manager.
export type Package = {
  dir: Path,
  name: Str,
  ver: Str,
  rel: Str,
  kind: PackageKind,
  deps: List[Str],
  mkdeps_host: List[Str],
  mkdeps_target: List[Str],
  upstream_sources: List[UpstreamSource],
  filetree: List[FileTreeEntry],
  nostrip: Bool,
  source_mirror: Bool,
}

## The sorted local package definitions and externally available names used for one graph resolution.
export type PackageCatalog = {root: Path, packages: List[Package], remote_names: List[Str]}

## Target and bootstrap rules that determine a package graph's build semantics.
export type BuildPolicy = {
  target: Target,
  build_target: Target,
  native_build: Bool,
  bootstrap_seeds: List[BootstrapSeedRule],
}

## The exact PM and XSH substrate that executes a build plan.
export type ExecutorIdentity = {
  format: Str,
  pm_sha256: Str,
  xsh_sha256: Str,
  core_sha256: Str,
}

## Immutable retrieval coordinates for an artifact reused from a remote snapshot.
export type RemoteRetrieval = {
  arch: Str,
  tarball: Str,
  tarball_sha256: Str,
  metadata: Str,
  metadata_sha256: Str,
}

## Remote artifact identity as observed while resolving one selected snapshot.
## Empty semantic fields represent legacy metadata and use the retrieval identity instead.
export type RemotePlanArtifact = {
  name: Str,
  ver: Str,
  rel: Str,
  retrieval: RemoteRetrieval,
  artifact_key: Str,
  recipe_sha256: Str,
  executor_sha256: Str,
  proof_key: Str,
  proof_sha256: Str,
}

## The selected immutable remote index snapshot used for a build-plan decision.
export type RemoteSnapshot = {
  target: Target,
  index_sha256: Str,
  packages: List[RemotePlanArtifact],
}

## One typed dependency reference in a durable build-plan node.
export type PlanDependency = {name: Str, kind: DependencyKind, artifact_key: Str}

## One deterministically ordered package build or remote-reuse operation.
export type PlanNode = {
  name: Str,
  ver: Str,
  rel: Str,
  package_id: Str,
  recipe_dir: Path,
  recipe_sha256: Str,
  proof_sha256: Str,
  artifact_key: Str,
  proof_key: Str,
  action: PlanAction,
  level: Int,
  dependencies: List[PlanDependency],
  remote: RemoteRetrieval?,
}

## One verified archive entry that can be installed into an immutable root.
## Paths and symlink targets remain text here because metadata JSON is a durable boundary.
export type ArtifactEntry = {path: Str, kind: FileKind, mode: Int, sha256: Str, target: Str}

## The completed, verified contents of one immutable package artifact directory.
export type ArtifactReceipt = {
  format: Str,
  key: Str,
  target: Target,
  package_name: Str,
  package_id: Str,
  origin: ArtifactOrigin,
  recipe_sha256: Str,
  executor_sha256: Str,
  payload_sha256: Str,
  metadata_sha256: Str,
  proof_key: Str,
  proof_sha256: Str,
  dependency_keys: List[Str],
  runtime_dependency_keys: List[Str],
  artifact_dir: Path,
}

## Files produced by a completed package build before immutable-store publication.
## The executor digest is staged explicitly because PlanNode carries only its artifact key.
export type StagedArtifact = {payload: Path, metadata: Path, proof: Path, executor_sha256: Str}

## One selected package artifact in a deterministic root-composition plan.
export type RootArtifact = {package_name: Str, package_id: Str, artifact_key: Str, payload: Bool}

## One root path together with its sole artifact owner and verified install metadata.
export type RootEntry = {
  package_name: Str,
  package_id: Str,
  artifact_key: Str,
  path: Str,
  kind: FileKind,
  mode: Int,
  sha256: Str,
  target: Str,
}

## The complete, deterministic ownership and payload plan for one immutable root.
export type RootPlan = {
  format: Str,
  target: Target,
  artifacts: List[RootArtifact],
  entries: List[RootEntry],
  root_sha256: Str,
}

## The durable receipt written into a completed immutable root.
export type RootReceipt = {
  format: Str,
  target: Target,
  artifacts: List[RootArtifact],
  entries: List[RootEntry],
  root_sha256: Str,
}

## A validated immutable package-build plan and its canonical digest.
export type BuildPlan = {
  format: Str,
  target: Target,
  roots: List[Str],
  repository_digest: Str,
  remote_index_sha256: Str,
  executor: ExecutorIdentity,
  nodes: List[PlanNode],
  plan_sha256: Str,
}

## The verified immutable artifacts produced or reused while executing one exact BuildPlan.
export type BuildResult = {format: Str, plan_sha256: Str, artifacts: List[ArtifactReceipt]}

## One runtime package selected from a BuildPlan for a complete system generation.
export type GenerationArtifact = {package_name: Str, package_id: Str, artifact_key: Str}

## Explicit profile-owned overlay metadata bound into a generation identity.
export type GenerationProfile = {name: Str, overlay_sha256: Str, replacements: List[Str]}

## The deterministic runtime-only projection of one verified BuildPlan.
export type GenerationPlan = {
  format: Str,
  target: Target,
  build_plan_sha256: Str,
  profile: GenerationProfile,
  runtime_roots: List[Str],
  artifacts: List[GenerationArtifact],
  generation_sha256: Str,
}

## The durable receipt for one completed system generation and its package-root provenance.
export type GenerationReceipt = {
  format: Str,
  generation_sha256: Str,
  build_plan_sha256: Str,
  profile: GenerationProfile,
  target: Target,
  runtime_roots: List[Str],
  artifacts: List[GenerationArtifact],
  root_sha256: Str,
}

## One verified package object selected from a completed BuildPlan for immutable repository publication.
export type RepoPublication = {
  node: PlanNode,
  receipt: ArtifactReceipt,
  payload: Path,
  metadata: Path,
  proof: Path,
  kind: PackageKind,
}

## The complete verified package set that may be published for one immutable BuildPlan.
export type RepoSnapshot = {
  format: Str,
  target: Target,
  plan_sha256: Str,
  packages: List[RepoPublication],
}

## A checksum recorded for an installed /etc file.
export type EtcSum = {path: Str, sha256: Str}

## A built package and its staged artifacts.
export type BuiltPackage = {
  pkg: Package,
  id: Str,
  tarball: Path,
  manifest: List[Path],
  etcsums: List[EtcSum],
  metadata_sha256: Str,
  metadata_files: List[ArtifactEntry],
}

## The compact package-index representation.
export type PackageIndex = {
  name: Str,
  ver: Str,
  rel: Str,
  deps: List[Str],
  mkdeps_host: List[Str],
  mkdeps_target: List[Str],
}

## A package advertised by a remote repository.
export type RemotePackage = {
  arch: Str,
  name: Str,
  ver: Str,
  rel: Str,
  deps: List[Str],
  mkdeps_host: List[Str],
  mkdeps_target: List[Str],
  sha256: Str,
  size: Int,
  tarball: Str,
  metadata: Str,
  metadata_sha256: Str,
  artifact_key: Str,
  recipe_sha256: Str,
  executor_sha256: Str,
  proof_key: Str,
  proof_sha256: Str,
  proof: Str,
  proof_receipt_sha256: Str,
  source_sha256: Str,
  metapackage: Bool,
}

## A source mapping declared by a package definition.
export type SourceLine = {source: Str, dest: Path}

## A source resolved to a local path and source kind.
export type ResolvedSource = {path: Path, kind: Str}

## A checksum field update produced by source commands.
export type ChecksumUpdate = {field: Str, values: List[Str]}

## Repository endpoints used by upload and export flows.
export type RepoUrls = {repo: Str, public_repo: Str}

## An uploaded source path and its content digest.
export type UploadedSource = {rel: Str, sha256: Str}
