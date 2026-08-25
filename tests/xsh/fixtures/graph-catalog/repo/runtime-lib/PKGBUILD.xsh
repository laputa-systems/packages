##! Graph catalog fixture package.
## Package name.
export let name = "runtime-lib"
## Explicit package classification.
export let package_kind = "meta"
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
## Metapackages have no payload files.
export let filetree = []
