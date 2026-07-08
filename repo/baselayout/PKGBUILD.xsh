export let name = "baselayout"

export let ver = "1"

export let rel = "14"

export let deps = []

export let mkdeps = []

export let sources = [p"files/rootfs"]

export let checksums = ["SKIP"]

export let extract_install = true

export proc build(dest: Path) [fs, error] {
  let _ = fs.copy_tree(p".", dest, parents: true, overwrite: true)?

  for keep in fs.walk(dest) |> where .kind == "file" and .name == ".keep" {
    keep.path.remove()?
  }
}
