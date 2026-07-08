export let name = "remote-meta"

export let ver = "1.0.0"

export let rel = "1"

export let deps = ["remote-app"]

export let mkdeps = []

export let sources = []

export let checksums = []

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  fs.mkdir(dest)?
}
