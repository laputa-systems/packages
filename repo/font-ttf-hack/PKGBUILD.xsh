##! XSH module `PKGBUILD` package and build operations.
export let name = "font-ttf-hack"

## Exported declaration `ver`.
export let ver = "3.003"

## Exported declaration `rel`.
export let rel = "9"

## Exported declaration `deps`.
export let deps = []

## Exported declaration `mkdeps_host`.
export let mkdeps_host = []

## Exported declaration `upstream_sources`.
export let upstream_sources = [
  {
    source: p"https://github.com/source-foundry/Hack/releases/download/vVERSION/Hack-vVERSION-ttf.tar.xz",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "d9ed5d0a07525c7e7bd587b4364e4bc41021dd668658d09864453d9bb374a78d",
      },
    ],
  },
]

## Exported declaration `filetree`.
export let filetree = [
  {
    path: p"usr/share/fonts/TTF/Hack-Bold.ttf",
    kind: "file",
  },
  {
    path: p"usr/share/fonts/TTF/Hack-BoldItalic.ttf",
    kind: "file",
  },
  {
    path: p"usr/share/fonts/TTF/Hack-Italic.ttf",
    kind: "file",
  },
  {
    path: p"usr/share/fonts/TTF/Hack-Regular.ttf",
    kind: "file",
  },
]

## Exported declaration `build`.
export proc build(dest: Path) [fs, error] {
  for entry in fs.ls(p".")? |> where .kind == "file" and .ext == "ttf" {
    fs.install(entry.path, fp"${dest}/usr/share/fonts/TTF/${entry.name}", 0o644, parents: true, overwrite: true)?
  }
}
