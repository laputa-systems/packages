export error PmError = Usage(message: Str) : Usage | MissingDependency(message: Str) : Dependency | DependencyCycle(message: Str) : Dependency | ExtensionFailed(message: Str) | LifecycleHook(message: Str) | PackageTarball(message: Str) : NotFound | PackageConflict(message: Str) : Conflict | DirtyFilesystem(message: Str) : Conflict | PackageContract(message: Str) : InvalidData | DependentPackage(message: Str) : Dependency | PackageNotInstalled(message: Str) : NotFound | RemoteRepo(message: Str) : Remote | Auth(message: Str) : PermissionDenied | RemoteFetch(message: Str) : Remote | RemoteUpload(message: Str) : Remote | RemoteIndex(message: Str) : Remote | RemotePackage(message: Str) : NotFound | SourceDestination(message: Str) : InvalidData | SourceName(message: Str) : InvalidData | DownloadFailed(message: Str) : Remote | DownloadTool(message: Str) : NotFound | SourceNotFound(message: Str) : NotFound | SourceChecksum(message: Str) : InvalidData | ChecksumField(message: Str) : InvalidData

# Minimal module contract for functions that only access a subset of
# let-bindings.  Avoids triggering proc/pure validation which requires
# live proc registries not available during general argument type checks.
export type PackageChecksumsContract = module {
  export let checksums: List[Str]
}

export type PackageExports = module {
  export let name: Str
  export let ver: Str
  export let rel: Str
  export let deps: List[Str]
  export let mkdeps: List[Str]
  export optional let target_build_deps: List[Str]
  export let sources: List[Path]
  export let checksums: List[Str]
  export proc build(dest: Path) [fs, process, env, error]
  export optional let nostrip: Bool
  export optional let checksums_aarch64: List[Str]
  export optional let checksums_x86_64: List[Str]
  export optional proc prepare(src: Path) [fs, process, env, error]
  export optional proc process_sources(src: Path) [fs, process, env, error]
  export optional proc pre_install(root: Path) [fs, process, env, error]
  export optional proc post_install(root: Path) [fs, process, env, error]
  export optional proc pre_remove(root: Path) [fs, process, env, error]
  export optional proc post_remove(root: Path) [fs, process, env, error]
  export optional let extract_install: Bool
}

export type Package = {
  dir: Path,
  exports: Any,
  name: Str,
  ver: Str,
  rel: Str,
  deps: List[Str],
  mkdeps: List[Str],
  target_build_deps: List[Str],
  sources: List[Path],
  checksums: List[Str],
  nostrip: Bool,
  extract_install: Bool,
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

export type PackageIndex = {name: Str, ver: Str, rel: Str, deps: List[Str], mkdeps: List[Str], target_build_deps: List[Str]}

export type RemotePackage = {
  arch: Str,
  name: Str,
  ver: Str,
  rel: Str,
  deps: List[Str],
  mkdeps: List[Str],
  target_build_deps: List[Str],
  sha256: Str,
  size: Int,
  tarball: Str,
  metadata: Str,
  source_sha256: Str,
  source_tarball: Str,
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
