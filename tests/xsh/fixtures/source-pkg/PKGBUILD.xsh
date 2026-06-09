export let name = "source-pkg"

export let ver = "1.0.0"

export let rel = "1"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources = [p"files/data.txt"]

export let checksums = ["0000000000000000000000000000000000000000000000000000000000000000"]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/share/source-pkg/data.txt"
  fs.mkdir(target.parent)?
  fs.install(p"data.txt", target, 0o644)?
}
