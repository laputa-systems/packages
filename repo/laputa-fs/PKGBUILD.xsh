export let name = "laputa-fs"

export let ver = "1"

export let rel = "3"

export let deps = ["xsh"]

export let mkdeps = []

export let sources = [p"files/mkfs.vfat.xsh", p"files/mkfs.ext4.xsh", p"files/fsck.ext4.xsh", p"files/fat-put.xsh"]

export let checksums = [
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
]

export proc build(dest: Path) [fs, error] {
  fs.install(p"mkfs.vfat.xsh", fp"${dest}/usr/bin/mkfs.vfat", 0o755, parents: true, overwrite: true)?
  fs.install(p"mkfs.ext4.xsh", fp"${dest}/usr/bin/mkfs.ext4", 0o755, parents: true, overwrite: true)?
  fs.install(p"fsck.ext4.xsh", fp"${dest}/usr/bin/fsck.ext4", 0o755, parents: true, overwrite: true)?
  fs.install(p"fat-put.xsh", fp"${dest}/usr/lib/laputa-fs/fat-put", 0o755, parents: true, overwrite: true)?
}
