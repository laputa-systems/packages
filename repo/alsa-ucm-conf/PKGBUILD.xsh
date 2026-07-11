export let name = "alsa-ucm-conf"

export let ver = "1.2.15.3"

export let rel = "6"

export let deps = ["alsa-lib"]

export let mkdeps = []

export let sources = [p"https://www.alsa-project.org/files/pub/lib/alsa-ucm-conf-VERSION.tar.bz2"]

export let checksums = [
  "9f79e813c08fc86cfa46dd75c4fcda1a4a51b482db2607e1fcfaafb92f588a31",
]

export proc build(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/usr/share/alsa")?
  let _ = fs.copy_tree(p"ucm2", fp"${dest}/usr/share/alsa/ucm2", parents: true, overwrite: true)?
}
