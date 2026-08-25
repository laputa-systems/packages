##! Valid metapackage recipe fixture.
## Package name.
export let name = "recipe-valid-meta"
## Explicit metapackage kind.
export let package_kind = "meta"
## Package version.
export let ver = "1.0.0"
## Package release.
export let rel = "1"
## Runtime dependencies.
export let deps = ["runtime"]
## Build-host dependencies.
export let mkdeps_host = []
## Metapackages have no source payload.
export let upstream_sources = []
## Metapackages have no file payload.
export let filetree = []
