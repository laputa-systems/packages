##! Minimal payload recipe for generation-overlay ownership coverage.
## Package name.
export let name = "baselayout"
## Explicit payload classification.
export let package_kind = "payload"
## Package version.
export let ver = "1"
## Package release.
export let rel = "1"
## Runtime dependencies.
export let deps = []
## Host build dependencies.
export let mkdeps_host = []
## Target build dependencies.
export let mkdeps_target = []
## Fixture sources.
export let upstream_sources = []
## Baseline init-hook directory supplied by the package root.
export let filetree = [{path: p"usr/lib/init/rc.d", kind: "tree"}]
## Builds the declared empty directory.
export proc build(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/usr/lib/init/rc.d", parents: true)?
}
