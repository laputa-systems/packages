export let name: Str = "m4"

export let ver: Str = "1.0"

export let rel: Str = "3"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = []

# m4 is implemented in pure XSH — no tarball, no compilation.
export let sources: List[Path] = [p"files/m4.xsh"]

export let checksums: List[Str] = ["SKIP"]

export proc build(dest: Path) [fs, error] {
  fs.install(p"m4.xsh", fp"${dest}/usr/bin/m4", 0o755, parents: true, overwrite: true)?
}
