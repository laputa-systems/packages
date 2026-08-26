##! XSH module `proof` package and build operations.
error ProofError = Failed(kind: Str, message: Str)

type RootArtifact = {package_name: Str, package_id: Str, artifact_key: Str, payload: Bool}
type RootReceipt = {format: Str, target: Str, artifacts: List[RootArtifact], entries: List[Any], root_sha256: Str}

proc ensure_exists(path_value: Path, label: Str) [fs, error] {
  if ! fs.exists(path_value)? {
    return Err(ProofError.Failed("proof-build-essential-native", f"missing ${label}: ${path_value.display()}"))
  }
}

proc ensure_runtime_artifacts(root: Path, packages: List[Str]) [fs, error] {
  let path_value = fp"${root}/var/lib/laputa/root.json"
  let receipt = json.read(path_value)?.require(RootReceipt)?

  if receipt.format != "laputa-root-1" or receipt.target != "aarch64-linux-musl" {
    return Err(ProofError.Failed("proof-build-essential-native", f"invalid typed root receipt: ${path_value.display()}"))
  }

  for package in packages {
    var found = false

    for artifact in receipt.artifacts {
      if artifact.package_name == package {
        found = true
      }
    }

    if ! found {
      return Err(ProofError.Failed("proof-build-essential-native", f"missing ${package} artifact in typed root receipt: ${path_value.display()}"))
    }
  }
}

proc main(root: Path = /rootfs) [fs, error] {
  for tool in [
    "cc",
    "c++",
    "pkg-config",
    "samu",
    "cmake",
    "m4",
    "flex",
    "bison",
    "muon",
  ] {
    ensure_exists(fp"${root}/usr/bin/${tool}", tool)?
  }

  ensure_exists(fp"${root}/boot/vmlinuz", "linux kernel image")?

  # The proof root is composed from verified immutable runtime receipts.  It
  # intentionally does not synthesize legacy package-manager database files.
  ensure_runtime_artifacts(root, [
    "llvm-toolchain",
    "musl",
    "pkgconf",
    "samurai",
    "cmake",
    "m4",
    "flex",
    "bison",
    "linux",
    "muon",
  ])?

  print "build-essential-native ok"
}

main(@args)?
