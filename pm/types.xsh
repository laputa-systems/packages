export error PmError = Usage(message: Str) : Usage | MissingDependency(message: Str) : Dependency | DependencyCycle(message: Str) : Dependency | ExtensionFailed(message: Str) | LifecycleHook(message: Str) | PackageTarball(message: Str) : NotFound | PackageConflict(message: Str) : Conflict | DirtyFilesystem(message: Str) : Conflict | PackageContract(message: Str) : InvalidData | DependentPackage(message: Str) : Dependency | PackageNotInstalled(message: Str) : NotFound | RemoteRepo(message: Str) : Remote | Auth(message: Str) : PermissionDenied | RemoteFetch(message: Str) : Remote | RemoteUpload(message: Str) : Remote | RemoteIndex(message: Str) : Remote | RemotePackage(message: Str) : NotFound | SourceDestination(message: Str) : InvalidData | SourceName(message: Str) : InvalidData | DownloadFailed(message: Str) : Remote | DownloadTool(message: Str) : NotFound | SourceNotFound(message: Str) : NotFound | SourceChecksum(message: Str) : InvalidData | ChecksumField(message: Str) : InvalidData

export type FileTreeEntry = {path: Path, kind: Str}

export type SourceChecksum = {arch: Str, sha256: Str}

export type UpstreamSource = {source: Path, kind: Str, architectures: List[Str], checksums: List[SourceChecksum]}

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

export type EtcSum = {path: Str, sha256: Str}

export type BuiltPackage = {
  pkg: Package,
  id: Str,
  tarball: Path,
  manifest: List[Path],
  etcsums: List[EtcSum],
  metadata_sha256: Str,
  metadata_files: List[Record],
}

export type PackageIndex = {
  name: Str,
  ver: Str,
  rel: Str,
  deps: List[Str],
  mkdeps_host: List[Str],
  mkdeps_target: List[Str],
}

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

export type SourceLine = {source: Str, dest: Path}

export type ResolvedSource = {path: Path, kind: Str}

export type ChecksumUpdate = {field: Str, values: List[Str]}

export type Extension = {name: Str, path: Path, summary: Str}

export type RepoUrls = {repo: Str, public_repo: Str}

export type UploadedSource = {rel: Str, sha256: Str}

export type Cli = {command: Str, action: Str, root: Path, work: Path, out: Path, raw: List[Str]}

export type PmContext = {command: Str, root: Path, work: Path, out: Path}
