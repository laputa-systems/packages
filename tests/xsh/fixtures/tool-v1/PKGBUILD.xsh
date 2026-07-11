export let name = "tool"

export let ver = "1.0.0"

export let rel = "1"

export let deps = []

export let mkdeps_host = []

export let sources = []

export let checksums = []

export let filetree = [{path: p"usr/bin/tool", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/bin/tool"
  fs.mkdir(target.parent)?

  fs.write(
    target,
    """v1
""",
  )?
}
