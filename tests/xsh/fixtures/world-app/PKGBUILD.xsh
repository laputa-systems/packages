export let name = "world-app"

export let ver = "1.0.0"

export let rel = "1"

export let deps = ["world-lib"]

export let mkdeps_host = []

export let sources = []

export let checksums = []

export let filetree = [{path: p"usr/share/world-app.txt", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/share/world-app.txt"
  fs.mkdir(target.parent)?

  fs.write(
    target,
    """world-app
""",
  )?
}
