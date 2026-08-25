##! Semantic fingerprint package fixture.
## Package name.
export let name = "fingerprint-package"
## Explicit package classification.
export let package_kind = "payload"
## Package version.
export let ver = "1.0.0"
## Package release.
export let rel = "1"
## Runtime dependencies.
export let deps = ["runtime"]
## Host build dependencies.
export let mkdeps_host = ["host-tool"]
## Target build dependencies.
export let mkdeps_target = ["target-sdk"]
## Declared source input.
export let upstream_sources = [{source: p"https://example.invalid/source.tar.xz", kind: "archive", architectures: ["all"], checksums: [{arch: "all", sha256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}]}]
## Declared payload files.
export let filetree = []
## Builds the fixture payload.
export proc build(dest: Path) [fs, error] {
  fs.mkdir(dest)?
}
