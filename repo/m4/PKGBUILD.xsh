export let name = "m4"

export let ver = "1.0"

export let rel = "9"

export let deps = ["musl"]

export let mkdeps_host = []

# m4 is implemented in pure XSH — no tarball, no compilation.
export let upstream_sources = [
  {
    source: p"files/m4.xsh",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "SKIP",
      },
    ],
  },
]

export let filetree = [{path: p"usr/bin/m4", kind: "file"}]

export proc build(dest: Path) [fs, error] {
  fs.install(p"m4.xsh", fp"${dest}/usr/bin/m4", 0o755, parents: true, overwrite: true)?
}
