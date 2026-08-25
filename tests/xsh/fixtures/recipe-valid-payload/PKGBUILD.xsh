##! Valid payload recipe fixture.
## Package name.
export let name = "recipe-valid-payload"
## Explicit package payload kind.
export let package_kind = "payload"
## Package version.
export let ver = "1.0.0"
## Package release.
export let rel = "1"
## Runtime dependencies.
export let deps = ["runtime"]
## Build-host dependencies.
export let mkdeps_host = ["builder"]
## Build-target dependencies.
export let mkdeps_target = []
## Upstream inputs.
export let upstream_sources = [{
  source: p"files/input.txt",
  kind: "auto",
  architectures: ["all"],
  checksums: [{arch: "all", sha256: "SKIP"}],
}]
## Declared package output.
export let filetree = [{path: p"usr/share/recipe-valid-payload.txt", kind: "file"}]
## Builds the payload.
export proc build(dest: Path) [fs, error] {
  fs.write(fp"${dest}/usr/share/recipe-valid-payload.txt", "payload")?
}
