export let name: Str = "xsh"

export let ver: Str = "0.0.0"

export let rel: Str = "4"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://github.com/laputa-systems/xsh/releases/download/release-c2b13e32617f226bff4bb207628143b4361aa32e/xsh-multicall-release-c2b13e32617f226bff4bb207628143b4361aa32e-ARCH-linux-musl.xz => xsh-multicall",
  p"https://github.com/laputa-systems/xsh/archive/c2b13e32617f226bff4bb207628143b4361aa32e.tar.gz => xsh-src",
]

export let checksums: List[Str] = ["SKIP", "37fdbd54dbf7443325acff7d57d58dbc42127970fe7911b1cfb478c9b0e05868"]

export let checksums_aarch64: List[Str] = [
  "de40171ecf14a38ab51361d9375b55c808dfba364785f9ca91c05332ad128cce",
  "37fdbd54dbf7443325acff7d57d58dbc42127970fe7911b1cfb478c9b0e05868",
]

export let checksums_x86_64: List[Str] = [
  "ee2f06985a598de1c3616f555026a89cedaec47ac889e1cf364356a850c0ee31",
  "37fdbd54dbf7443325acff7d57d58dbc42127970fe7911b1cfb478c9b0e05868",
]

export let nostrip: Bool = true

error XshPackageError = Source(message: Str)

export proc process_sources(src: Path) [fs, error] {
  let staged = fs.children(fp"${src}/xsh-multicall")? |> where .kind == "file" and .name.ends_with(".xz")

  if staged.len() != 1 {
    return Err(XshPackageError.Source("expected one staged xsh multicall release artifact"))
  }

  let binary = fp"${src}/xsh-multicall/${staged[0].name.replace(".xz", "")}"
  archive.decompress(staged[0].path, binary, "auto", true)?

  if ! fs.exists(binary)? {
    return Err(XshPackageError.Source("expected decompressed xsh multicall release artifact"))
  }
}

export proc build(dest: Path) [fs, error] {
  let staged = fs.children(p"xsh-multicall")? |> where .kind == "file" and ! .name.ends_with(".xz")

  if staged.len() != 1 {
    return Err(XshPackageError.Source("expected one decompressed xsh multicall release artifact"))
  }

  fs.install(staged[0].path, fp"${dest}/usr/local/bin/xsh", 0o755, parents: true, overwrite: true)?

  for command_name in ["xshi", "xsht"] {
    let link = fp"${dest}/usr/local/bin/${command_name}"
    fs.remove(link, missing_ok: true)?
    fs.symlink(p"xsh", link)?
  }

  let _ = fs.copy_tree(p"xsh-src/core", fp"${dest}/usr/lib/xsh/core", parents: true, overwrite: true)?
  fs.remove(fp"${dest}/usr/lib/xsh/core/xinit.xsh", missing_ok: true)?

  for entry in fs.walk(fp"${dest}/usr/lib/xsh/core", gitignore: false)? |> where .kind == "file" and .ext == "xsh" {
    fs.chmod(entry.path, 0o755)?
  }
}

export proc pre_install(root: Path) [fs, error] {
  fs.remove(fp"${root}/usr/local/bin/xsh-multicall", missing_ok: true)?

  for command_name in ["xsh", "xshi", "xsht"] {
    fs.remove(fp"${root}/usr/local/bin/${command_name}", missing_ok: true)?
  }
}