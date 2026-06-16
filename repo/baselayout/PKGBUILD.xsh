export let name: Str = "baselayout"

export let ver: Str = "1"

export let rel: Str = "14"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = [p"files/rootfs"]

export let checksums: List[Str] = ["SKIP"]

export let extract_install: Bool = true

export proc build(dest: Path) [fs, error] {
  let _ = fs.copy_tree(p".", dest, parents: true, overwrite: true)?

  for keep in fs.walk(dest) |> where .kind == "file" and .name == ".keep" {
    keep.path.remove()?
  }
}
