##! Payload fixture that leaves an undeclared empty parent directory.
## Fixture package name.
export let name = "recipe-empty-parent"
## Explicit payload classification.
export let package_kind = "payload"
## Fixture package version.
export let ver = "1.0.0"
## Fixture package release.
export let rel = "1"
## Fixture runtime dependencies.
export let deps = []
## Fixture host build dependencies.
export let mkdeps_host = []
## Fixture source inputs.
export let upstream_sources = []
## Fixture payload declarations.
export let filetree = [{path: p"usr/bin/recipe-empty-parent", kind: "file"}]

## Creates a payload file and removes the only child of an incidental directory.
export proc build(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/usr/bin", parents: true)?
  fs.write(fp"${dest}/usr/bin/recipe-empty-parent", "payload")?
  fs.mkdir(fp"${dest}/usr/share/man", parents: true)?
  fs.remove(fp"${dest}/usr/share/man")?
}
