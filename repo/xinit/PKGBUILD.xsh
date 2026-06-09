export let name: Str = "xinit"

export let ver: Str = "fbd5008b9928808ed815849d9a44f43bc8b2bfd5"

export let rel: Str = "2"

export let deps: List[Str] = ["xsh"]

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://raw.githubusercontent.com/laputa-systems/xinit/VERSION/xinit.xsh => xinit",
]

export let checksums: List[Str] = ["74c81ca48e466fed707dd52d5d4d59671cc73b5aa8ce9d8c6f53d14fc082da59"]

export let checksums_aarch64: List[Str] = ["74c81ca48e466fed707dd52d5d4d59671cc73b5aa8ce9d8c6f53d14fc082da59"]

export let checksums_x86_64: List[Str] = ["74c81ca48e466fed707dd52d5d4d59671cc73b5aa8ce9d8c6f53d14fc082da59"]

export let nostrip: Bool = true

export proc build(dest: Path) [fs, error] {
  fs.install(p"xinit/xinit.xsh", fp"${dest}/usr/bin/xinit", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"xinit", fp"${dest}/usr/bin/init")?
  fs.symlink(p"usr/bin/xinit", fp"${dest}/init")?
}
