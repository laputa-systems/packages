export let name: Str = "xinit"

export let ver: Str = "release-f9034b48f96f49f42914498cd7bbe8a080b945b3"

export let rel: Str = "2"

export let deps: List[Str] = ["xsh"]

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://github.com/laputa-systems/xsh/releases/download/VERSION/xsh-VERSION-ARCH-linux-musl.tar.gz => xsh",
]

export let checksums: List[Str] = ["SKIP"]

export let checksums_aarch64: List[Str] = ["a660ca00a215960d4d70ae2fbd329796793b1357ac693da517a7bdec45265d98"]

export let checksums_x86_64: List[Str] = ["11b035a88c4bac2672da3dbdb400a6258d24d944a990659776e8850619e9369c"]

export let nostrip: Bool = true

export proc build(dest: Path) [fs, error] {
  fs.install(p"xsh/usr/bin/xinit", fp"${dest}/usr/bin/xinit", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"xinit", fp"${dest}/usr/bin/init")?
  fs.symlink(p"usr/bin/xinit", fp"${dest}/init")?
}
