export let name: Str = "hwdata"

export let ver: Str = "0.400"

export let rel: Str = "3"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = [p"https://github.com/vcrhonek/hwdata/archive/refs/tags/vVERSION.tar.gz"]

export let checksums: List[Str] = ["05d96821aaae04be4e684eaf9ac22e08efe646321bc64be323b91b66e7e2095c"]

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
