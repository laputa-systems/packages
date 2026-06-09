export let name = "laputa-pm"

export let ver = "1.0.0"

export let rel = "1"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = []

export let checksums: List[Str] = []

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/bin/cat"
  fs.mkdir(target.parent)?

  fs.write(
    target,
    """cat
""",
  )?
}
