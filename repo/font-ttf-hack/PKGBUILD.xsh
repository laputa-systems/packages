export let name = "font-ttf-hack"

export let ver = "3.003"

export let rel = "3"

export let deps = []

export let mkdeps = []

export let sources = [
  p"https://github.com/source-foundry/Hack/releases/download/vVERSION/Hack-vVERSION-ttf.tar.xz",
]

export let checksums = [
  "d9ed5d0a07525c7e7bd587b4364e4bc41021dd668658d09864453d9bb374a78d",
]

export proc build(dest: Path) [fs, error] {
  for entry in fs.ls(p".")? |> where .kind == "file" and .ext == "ttf" {
    fs.install(entry.path, fp"${dest}/usr/share/fonts/TTF/${entry.name}", 0o644, parents: true, overwrite: true)?
  }
}
