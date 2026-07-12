export let name = "extract-tree"

export let ver = "1.0.0"

export let rel = "1"

export let deps = []

export let mkdeps_host = []

export let upstream_sources = [
  {source: p"files/rootfs", kind: "auto", architectures: ["all"], checksums: [{arch: "all", sha256: "SKIP"}]},
]

export let filetree = [
  {path: p"bin", kind: "symlink"},
  {path: p"etc/extract-tree.conf", kind: "file"},
  {path: p"usr/bin/extract-tree", kind: "file"},
]

export let extract_install = true

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let _ = fs.copy_tree(p".", dest, parents: true, overwrite: true)?

  for keep in fs.walk(dest) |> where .kind == "file" and .name == ".keep" {
    keep.path.remove()?
  }
}
