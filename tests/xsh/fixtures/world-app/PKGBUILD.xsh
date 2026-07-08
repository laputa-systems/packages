export let name = "world-app"

export let ver = "1.0.0"

export let rel = "1"

export let deps = ["world-lib"]

export let mkdeps = []

export let sources = []

export let checksums = []

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/share/world-app.txt"
  fs.mkdir(target.parent)?

  fs.write(
    target,
    """world-app
""",
  )?
}
