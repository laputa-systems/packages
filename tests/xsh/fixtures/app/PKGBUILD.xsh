export let name = "app"

export let ver = "1.0.0"

export let rel = "1"

export let deps: List[Str] = ["dep"]

export let mkdeps: List[Str] = ["llvm-toolchain"]

export let sources: List[Path] = []

export let checksums: List[Str] = []

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/share/app.txt"
  fs.mkdir(target.parent)?

  fs.write(
    target,
    """app
""",
  )?
}
