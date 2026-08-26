##! XSH module `proof-rootfs` package and build operations.
error ScriptError = Failed(kind: Str, message: Str)

type RootArtifact = {package_name: Str, package_id: Str, artifact_key: Str, payload: Bool}
type RootReceipt = {format: Str, target: Str, artifacts: List[RootArtifact], entries: List[Any], root_sha256: Str}

proc ensure_exists(path_value: Path, label: Str) [fs, error] {
  if ! fs.exists(path_value)? {
    return Err(ScriptError.Failed("proof-build-essential-native-rootfs", f"missing ${label}: ${path_value.display()}"))?
  }
}

proc ensure_runtime_artifacts(rootfs: Path, packages: List[Str]) [fs, error] {
  let path_value = fp"${rootfs}/var/lib/laputa/root.json"
  let receipt = json.read(path_value)?.require(RootReceipt)?

  if receipt.format != "laputa-root-1" or receipt.target != "aarch64-linux-musl" {
    return Err(ScriptError.Failed("proof-build-essential-native-rootfs", f"invalid typed root receipt: ${path_value.display()}"))
  }

  for package in packages {
    var found = false

    for artifact in receipt.artifacts {
      if artifact.package_name == package {
        found = true
      }
    }

    if ! found {
      return Err(ScriptError.Failed("proof-build-essential-native-rootfs", f"missing ${package} artifact in typed root receipt: ${path_value.display()}"))
    }
  }
}

proc main(rootfs: Path = /proof-rootfs) [fs, error] {
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
    ensure_exists(fp"${rootfs}/usr/bin/${tool}", tool)?
  }

  ensure_exists(fp"${rootfs}/boot/vmlinuz", "linux kernel image")?

  # Final roots retain the same verified immutable receipt contract as proof
  # roots; no legacy package-manager database is synthesized for validation.
  ensure_runtime_artifacts(rootfs, [
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

  print "build-essential-native rootfs ok"
}

main(@args)?
