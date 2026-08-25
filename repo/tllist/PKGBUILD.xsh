##! Package recipe metadata and build operations.
## Package recipe export.
export let name = "tllist"

## Explicit payload or metapackage classification.
export let package_kind = "payload"

## Package recipe export.
export let ver = "1.1.0"

## Package recipe export.
export let rel = "9"

## Package recipe export.
export let deps = []

## Package recipe export.
export let mkdeps_host = []

## Package recipe export.
export let upstream_sources = [
  {
    source: p"https://codeberg.org/dnkl/tllist/archive/VERSION.tar.gz",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "0e7b7094a02550dd80b7243bcffc3671550b0f1d8ba625e4dff52517827d5d23",
      },
    ],
  },
]

## Package recipe export.
export let filetree = [
  {
    path: p"usr/include/tllist.h",
    kind: "file",
  },
  {
    path: p"usr/lib/pkgconfig/tllist.pc",
    kind: "file",
  },
]

## Package recipe export.
export proc build(dest: Path) [fs, error] {
  fs.install(p"tllist.h", fp"${dest}/usr/include/tllist.h", 0o644, parents: true, overwrite: true)?
  fs.mkdir(fp"${dest}/usr/lib/pkgconfig")?

  fs.write(
    fp"${dest}/usr/lib/pkgconfig/tllist.pc",
    f"""prefix=/usr
includedir=\${prefix}/include

Name: tllist
Description: Typed linked list C header-only library
Version: ${ver}
Cflags: -I\${includedir}
""",
  )?
}
