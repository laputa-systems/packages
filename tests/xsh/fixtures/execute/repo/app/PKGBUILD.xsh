##! Executor fixture that requires both runtime and build-host dependency roots.
export let name = "execute-app"
export let package_kind = "payload"
export let ver = "1.0.0"
export let rel = "1"
export let deps = ["execute-dep"]
export let mkdeps_host = ["execute-tool"]
export let mkdeps_target = []
export let upstream_sources = []
export let filetree = [{path: p"usr/share/execute-app.txt", kind: "file"}]

export proc build(dest: Path) [fs, env, error] -> Result[Unit] {
  let root = env("LAPUTA_ROOT")?
  let _ = fs.read_text(fp"${root}/usr/share/execute-dep.txt")?
  let _ = fs.read_text(fp"${root}/usr/share/execute-tool.txt")?

  let target = fp"${dest}/usr/share/execute-app.txt"
  fs.mkdir(target.parent)?
  fs.write(target, "application v1\n")?
}
