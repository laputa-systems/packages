##! Shared package-manager error, metadata, and context types.
## The package-manager error family is returned by PM operations.
export error PmError = Usage(message: Str) : Usage | MissingDependency(message: Str) : Dependency | DependencyCycle(message: Str) : Dependency | ExtensionFailed(message: Str) | LifecycleHook(message: Str) | PackageTarball(message: Str) : NotFound | PackageConflict(message: Str) : Conflict | DirtyFilesystem(message: Str) : Conflict | PackageContract(message: Str) : InvalidData | DependentPackage(message: Str) : Dependency | PackageNotInstalled(message: Str) : NotFound | RemoteRepo(message: Str) : Remote | Auth(message: Str) : PermissionDenied | RemoteFetch(message: Str) : Remote | RemoteUpload(message: Str) : Remote | RemoteIndex(message: Str) : Remote | RemotePackage(message: Str) : NotFound | SourceDestination(message: Str) : InvalidData | SourceName(message: Str) : InvalidData | DownloadFailed(message: Str) : Remote | DownloadTool(message: Str) : NotFound | SourceNotFound(message: Str) : NotFound | SourceChecksum(message: Str) : InvalidData | ChecksumField(message: Str) : InvalidData

## A declared package output path and its kind.
export type FileTreeEntry = {path: Path, kind: Str}

## A source checksum keyed by target architecture.
export type SourceChecksum = {arch: Str, sha256: Str}

## An upstream source and the architectures it serves.
export type UpstreamSource = {source: Path, kind: Str, architectures: List[Str], checksums: List[SourceChecksum]}

## The public values exported by a package definition.
export type PackageExports = module {
  export let name: Str
  export let ver: Str
  export let rel: Str
  export let deps: List[Str]
  export let mkdeps_host: List[Str]
  export optional let mkdeps_target: List[Str]
  export let upstream_sources: List[UpstreamSource]
  export let filetree: List[FileTreeEntry]
  export optional let nostrip: Bool
  export optional let filetree_aarch64: List[FileTreeEntry]
  export optional let filetree_x86_64: List[FileTreeEntry]
  export optional let extract_install: Bool
  export optional let source_mirror: Bool
}

## A normalized package definition loaded by the package manager.
export type Package = {
  dir: Path,
  exports: Any,
  name: Str,
  ver: Str,
  rel: Str,
  deps: List[Str],
  mkdeps_host: List[Str],
  mkdeps_target: List[Str],
  upstream_sources: List[UpstreamSource],
  filetree: List[FileTreeEntry],
  nostrip: Bool,
  extract_install: Bool,
  source_mirror: Bool,
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
  metadata_files: List[Record],
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
  source_sha256: Str,
  metapackage: Bool,
}

## A source mapping declared by a package definition.
export type SourceLine = {source: Str, dest: Path}

## A source resolved to a local path and source kind.
export type ResolvedSource = {path: Path, kind: Str}

## A checksum field update produced by source commands.
export type ChecksumUpdate = {field: Str, values: List[Str]}

## A discovered PM extension executable.
export type Extension = {name: Str, path: Path, summary: Str}

## Repository endpoints used by upload and export flows.
export type RepoUrls = {repo: Str, public_repo: Str}

## An uploaded source path and its content digest.
export type UploadedSource = {rel: Str, sha256: Str}

## Parsed PM command-line arguments.
export type Cli = {command: Str, action: Str, root: Path, work: Path, out: Path, raw: List[Str]}

## Shared context passed between PM command adapters.
export type PmContext = {command: Str, root: Path, work: Path, out: Path}
