##! Absolute local SKIP checksum rejection fixture.
## Package name.
export let name = "recipe-absolute-skip"
## Explicit package classification.
export let package_kind = "payload"
## Package version.
export let ver = "1.0.0"
## Package release.
export let rel = "1"
## Runtime dependencies.
export let deps = []
## Host build dependencies.
export let mkdeps_host = []
## Absolute inputs are not repository-local.
export let upstream_sources = [{source: p"/tmp/foo", kind: "auto", architectures: ["all"], checksums: [{arch: "all", sha256: "SKIP"}]}]
## Payload files.
export let filetree = []
## Fixture payload build.
export proc build(dest: Path) [fs, error] {
  fs.mkdir(dest)?
}
