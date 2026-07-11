export let name = "build-essential-native"

export let ver = "1"

export let rel = "8"

export let deps = [
  "ca-certificates",
  "musl",
  "zlib",
  "llvm-toolchain",
  "pkgconf",
  "samurai",
  "cmake",
  "m4",
  "flex",
  "bison",
  "linux",
  "muon",
]

export let mkdeps_host = []

export let sources = []

export let checksums = []

export let filetree = []

export proc build(dest: Path) [fs, error] {
  fs.mkdir(dest)?
}
