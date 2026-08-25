##! Executor fixture runtime dependency.
export let name = "execute-dep"
export let package_kind = "payload"
export let ver = "1.0.0"
export let rel = "1"
export let deps = []
export let mkdeps_host = []
export let mkdeps_target = []
export let upstream_sources = []
export let filetree = [{path: p"usr/share/execute-dep.txt", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/share/execute-dep.txt"
  fs.mkdir(target.parent)?
  fs.write(target, "dependency\n")?
}
