##! Executor fixture host build dependency.
export let name = "execute-tool"
export let package_kind = "payload"
export let ver = "1.0.0"
export let rel = "1"
export let deps = []
export let mkdeps_host = []
export let mkdeps_target = []
export let upstream_sources = []
export let filetree = [{path: p"usr/share/execute-tool.txt", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/share/execute-tool.txt"
  fs.mkdir(target.parent)?
  fs.write(target, "tool\n")?
}
