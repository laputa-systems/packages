export let name: Str = "build-essential-native"

export let ver: Str = "1"

export let rel: Str = "3"

export let deps: List[Str] = [
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

export let mkdeps: List[Str] = []

export let sources: List[Path] = []

export let checksums: List[Str] = []

export proc build(dest: Path) [fs, error] {
  fs.mkdir(dest)?
}
