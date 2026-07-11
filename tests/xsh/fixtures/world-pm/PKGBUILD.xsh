export let name = "laputa-pm"

export let ver = "1.0.0"

export let rel = "1"

export let deps = []

export let mkdeps = []

export let sources = []

export let checksums = []

export let filetree = [{path: p"usr/bin/cat", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/bin/cat"
  fs.mkdir(target.parent)?

  fs.write(
    target,
    """cat
""",
  )?
}
