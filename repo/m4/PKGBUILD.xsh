##! Package recipe metadata and build operations.
## Package recipe export.
export let name = "m4"

## Explicit payload or metapackage classification.
export let package_kind = "payload"

## Package recipe export.
export let ver = "1.0"

## Package recipe export.
export let rel = "10"

## Package recipe export.
export let deps = ["musl"]

## Package recipe export.
export let mkdeps_host = []

# m4 is implemented in pure XSH — no tarball, no compilation.
## Package recipe export.
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

## Package recipe export.
export let filetree = [{path: p"usr/bin/m4", kind: "file"}]

## Package recipe export.
export proc build(dest: Path) [fs, error] {
  fs.install(p"m4.xsh", fp"${dest}/usr/bin/m4", 0o755, parents: true, overwrite: true)?
}
