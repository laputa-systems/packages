export let name = "extract-tree"

export let ver = "1.0.0"

export let rel = "1"

export let deps = []

export let mkdeps = []

export let sources = [p"files/rootfs"]

export let checksums = ["SKIP"]

export let extract_install = true

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let _ = fs.copy_tree(p".", dest, parents: true, overwrite: true)?

  for keep in fs.walk(dest) |> where .kind == "file" and .name == ".keep" {
    keep.path.remove()?
  }
}
