##! XSH module `PKGBUILD` package and build operations.
## Package recipe export.
export let name = "hwdata"

## Explicit payload or metapackage classification.
export let package_kind = "payload"

## Exported declaration `ver`.
export let ver = "0.400"

## Exported declaration `rel`.
export let rel = "9"

## Exported declaration `deps`.
export let deps = []

## Exported declaration `mkdeps_host`.
export let mkdeps_host = []

## Exported declaration `upstream_sources`.
export let upstream_sources = [
  {
    source: p"https://github.com/vcrhonek/hwdata/archive/refs/tags/vVERSION.tar.gz",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "05d96821aaae04be4e684eaf9ac22e08efe646321bc64be323b91b66e7e2095c",
      },
    ],
  },
]

## Exported declaration `filetree`.
export let filetree = [
  {
    path: p"usr/share/hwdata/pci.ids",
    kind: "file",
  },
  {
    path: p"usr/share/hwdata/pnp.ids",
    kind: "file",
  },
  {
    path: p"usr/share/pkgconfig/hwdata.pc",
    kind: "file",
  },
]

## Exported declaration `build`.
export proc build(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/usr/share/hwdata")?
  fs.install(p"pnp.ids", fp"${dest}/usr/share/hwdata/pnp.ids", 0o644, parents: true, overwrite: true)?
  fs.install(p"pci.ids", fp"${dest}/usr/share/hwdata/pci.ids", 0o644, parents: true, overwrite: true)?
  fs.mkdir(fp"${dest}/usr/share/pkgconfig")?

  fs.write(
    fp"${dest}/usr/share/pkgconfig/hwdata.pc",
    """prefix=/usr
datadir=\${prefix}/share
pkgdatadir=\${datadir}/hwdata

Name: hwdata
Description: Hardware identification data
Version: 0.400
""",
  )?
}
