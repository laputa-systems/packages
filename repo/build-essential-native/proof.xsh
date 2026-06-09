error ProofError = Failed(kind: Str, message: Str)

proc ensure_exists(path_value: Path, label: Str) [fs, error] {
  if ! fs.exists(path_value)? {
    return Err(ProofError.Failed("proof-build-essential-native", f"missing ${label}: ${path_value.display()}"))
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

  for package in [
    "baselayout",
    "build-essential-native",
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
  ] {
    ensure_exists(fp"${root}/var/lib/xsh-pm/packages/${package}/metadata.json", f"${package} package db")?
  }

  print "build-essential-native ok"
}

main(@args)?
