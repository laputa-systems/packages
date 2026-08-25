##! XSH module `PKGBUILD` package and build operations.
## Package recipe export.
export let name = "build-essential-native"

## Explicit payload or metapackage classification.
export let package_kind = "meta"

## Exported declaration `ver`.
export let ver = "1"

## Exported declaration `rel`.
export let rel = "9"

## Exported declaration `deps`.
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

## Exported declaration `mkdeps_host`.
export let mkdeps_host = []

## Exported declaration `upstream_sources`.
export let upstream_sources = []

## Exported declaration `filetree`.
export let filetree = []

## Exported declaration `build`.
export proc build(dest: Path) [fs, error] {
  fs.mkdir(dest)?
}
