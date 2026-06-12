export let name: Str = "xinit"

export let ver: Str = "local-service-graph"

export let rel: Str = "1"

export let deps: List[Str] = ["xsh"]

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://github.com/laputa-systems/xinit/raw/17b5fe2cb1b261a02b8950c66ff1c9b5a135368e/xinit.xsh",
]

export let checksums: List[Str] = [""]

export let checksums_aarch64 = [
  "2e4437d4746860393a16b967632ae1802e1ca73dcb0cf61e40e4278e9af93766",
]

export let checksums_x86_64 = [
  "2e4437d4746860393a16b967632ae1802e1ca73dcb0cf61e40e4278e9af93766",
]

export let nostrip: Bool = true

export proc build(dest: Path) [fs, error] {
  fs.install(p"xinit.xsh", fp"${dest}/usr/bin/xinit", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"xinit", fp"${dest}/usr/bin/init")?
  fs.symlink(p"usr/bin/xinit", fp"${dest}/init")?
}
