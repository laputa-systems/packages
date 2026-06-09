error ScriptError = Failed(kind: Str, message: Str)

type PackagePin = {version: Str, sha256: Str}

let llvm_version = "22.1.3"
let alpine_release = "22.1.3-r0"
let alpine_repo = "https://dl-cdn.alpinelinux.org/alpine/edge/main"

let llvm_packages = [
  "clang22",
  "clang22-headers",
  "clang22-libs",
  "compiler-rt",
  "lld22",
  "lld22-libs",
  "llvm-libunwind",
  "llvm-libunwind-dev",
  "llvm22",
  "llvm22-dev",
  "llvm22-libs",
  "llvm22-linker-tools",
]

let runtime_packages = [
  "brotli-libs",
  "c-ares",
  "ca-certificates-bundle",
  "fortify-headers",
  "libcrypto3",
  "libcurl",
  "libffi",
  "libgcc",
  "libidn2",
  "libpsl",
  "libssl3",
  "libstdc++",
  "libstdc++-dev",
  "libunistring",
  "libxml2",
  "nghttp2-libs",
  "xz-libs",
  "zstd-libs",
]

pure valid_arch(arch: Str) -> Bool {
  return arch == "aarch64" or arch == "x86_64"
}

proc pinned_package(lock: Path, arch: Str, pkg: Str) [process, error] -> Result[PackagePin] {
  let script = """awk -v arch='ARCH' -v pkg='PKG' '$1 == arch && $2 == pkg { print $3 " " $4; exit }' "LOCK"
""".replace("ARCH", arch).replace("PKG", pkg).replace("LOCK", lock.display())

  let pinned = run.text "sh" "-c" $script ?
  let fields = pinned.words()

  if fields.len() != 2 {
    return Err(
      ScriptError.Failed("llvm-package-lock", f"package ${pkg} for ${arch} is not pinned in ${lock.display()}"),
    )
  }

  return {version: fields[0], sha256: fields[1]}
}

proc verify_apk(apk: Path, expected_sha256: Str) [fs, error] -> Result[Bool] {
  if ! apk.exists()? {
    return false
  }

  let actual = hash.sha256(apk)?.hex()

  if actual == expected_sha256 {
    return true
  }

  fs.remove(apk, missing_ok: true)?
  return false
}

proc extract_package(root: Path, apk: Path) [process, error] {
  run (
    "tar"
    "-xzf"
    $apk
    "-C"
    $root
    "--exclude=.SIGN.*"
    "--exclude=.PKGINFO"
    "--exclude=.DESCRIPTION"
    "--exclude=.INSTALL"
    "--exclude=.trigger*"
  ) ?
}

proc fetch_pinned_package(root: Path, cache: Path, lock: Path, arch: Str, pkg: Str) [fs, process, error] {
  let pinned = pinned_package(lock, arch, pkg)?
  let apk = fp"${cache}/${pkg}-${pinned.version}.apk"
  let url = f"${alpine_repo}/${arch}/${pkg}-${pinned.version}.apk"

  if ! verify_apk(apk, pinned.sha256)? {
    run "curl" "-fsSL" "-o" $apk $url ?
  }

  if ! verify_apk(apk, pinned.sha256)? {
    return Err(
      ScriptError.Failed("llvm-package-sha256", f"${pkg} ${pinned.version} for ${arch} did not match pinned sha256"),
    )
  }

  extract_package(root, apk)?
}

proc normalize_payload(root: Path) [fs, error] {
  fs.remove(fp"${root}/etc/ssl1.1", missing_ok: true)?

  for path_value in [
    fp"${root}/usr/bin/gcc",
    fp"${root}/usr/bin/g++",
    fp"${root}/usr/bin/cpp",
    fp"${root}/usr/bin/cc",
    fp"${root}/usr/bin/c++",
    fp"${root}/usr/bin/ld",
    fp"${root}/usr/bin/ar",
    fp"${root}/usr/bin/ranlib",
    fp"${root}/usr/bin/nm",
    fp"${root}/usr/bin/objcopy",
    fp"${root}/usr/bin/objdump",
    fp"${root}/usr/bin/readelf",
    fp"${root}/usr/bin/strip",
  ] {
    fs.remove(path_value, missing_ok: true)?
  }
}

proc build_arch(arch: Str) [fs, process, error] {
  if ! valid_arch(arch) {
    return Err(ScriptError.Failed("llvm-toolchain-arch", f"unsupported arch ${arch}"))
  }

  let files = p"files"
  let lock = p"package-lock.txt"
  let work = fp"${files}/work-${arch}"
  let cache = fp"${work}/apk"
  let root = fp"${work}/root"
  let out = fp"${files}/llvm-toolchain-${llvm_version}-${arch}.tar.gz"
  fs.remove(work, missing_ok: true)?
  fs.mkdir(cache)?
  fs.mkdir(root)?

  for pkg in llvm_packages {
    fetch_pinned_package(root, cache, lock, arch, pkg)?
  }

  for pkg in runtime_packages {
    fetch_pinned_package(root, cache, lock, arch, pkg)?
  }

  normalize_payload(root)?
  archive.tar_create(out, work, [p"root"], compression: "gz", overwrite: true)?
  print f"${out.display()} ${hash.sha256(out)?.hex()}"
}

proc main(...argv: List[Str]) [fs, process, env, error] {
  var arches = argv

  if arches.len() == 0 {
    let os = system.uname()?
    arches = [if os.machine == "arm64" { "aarch64" } else { os.machine }]
  }

  for arch in arches {
    build_arch(arch)?
  }
}

main(@args)?
