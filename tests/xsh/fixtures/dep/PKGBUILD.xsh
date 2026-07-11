export let name = "dep"

export let ver = "1.0.0"

export let rel = "1"

export let deps = []

export let mkdeps_host = ["make"]

export let sources = []

export let checksums = []

export let filetree = [{path: p"usr/share/dep.txt", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/share/dep.txt"
  fs.mkdir(target.parent)?

  fs.write(
    target,
    """dep
""",
  )?
}
