export let name = "m4"

export let ver = "1.0"

export let rel = "3"

export let deps = ["musl"]

export let mkdeps = []

# m4 is implemented in pure XSH — no tarball, no compilation.
export let sources = [p"files/m4.xsh"]

export let checksums = ["SKIP"]

export proc build(dest: Path) [fs, error] {
  fs.install(p"m4.xsh", fp"${dest}/usr/bin/m4", 0o755, parents: true, overwrite: true)?
}
