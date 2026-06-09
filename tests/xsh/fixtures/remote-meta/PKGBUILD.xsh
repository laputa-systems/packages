export let name = "remote-meta"

export let ver = "1.0.0"

export let rel = "1"

export let deps: List[Str] = ["remote-app"]

export let mkdeps: List[Str] = []

export let sources: List[Path] = []

export let checksums: List[Str] = []

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  fs.mkdir(dest)?
}
