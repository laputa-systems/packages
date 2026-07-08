export let name = "app"

export let ver = "1.0.0"

export let rel = "1"

export let deps = ["dep"]

export let mkdeps = ["llvm-toolchain"]

export let sources = []

export let checksums = []

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/share/app.txt"
  fs.mkdir(target.parent)?

  fs.write(
    target,
    """app
""",
  )?
}
