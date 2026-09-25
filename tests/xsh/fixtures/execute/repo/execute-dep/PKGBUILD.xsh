##! Executor fixture runtime dependency.
## Package name.
export let name = "execute-dep"
## Payload kind.
export let package_kind = "payload"
## Package version.
export let ver = "1.0.0"
## Package release.
export let rel = "1"
## No runtime dependencies.
export let deps = []
## No build-host dependencies.
export let mkdeps_host = []
## No build-target dependencies.
export let mkdeps_target = []
## No upstream source inputs.
export let upstream_sources = []
## Declared output.
export let filetree = [{path: p"usr/share/execute-dep.txt", kind: "file"}]

## Builds the runtime dependency payload.
export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/share/execute-dep.txt"
  fs.mkdir(target.parent)?
  fs.write(target, "dependency\n")?
}
