export let name: Str = "xsh"

export let ver: Str = "release-f46249e1647af0ffb9cc7abf6592218029c30ff1"

export let rel: Str = "4"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://github.com/laputa-systems/xsh/releases/download/VERSION/xsh-multicall-VERSION-ARCH-linux-musl.xz => xsh-multicall",
  p"https://github.com/laputa-systems/xsh/archive/f46249e1647af0ffb9cc7abf6592218029c30ff1.tar.gz => xsh-src",
]

export let checksums: List[Str] = ["SKIP", "ddefcdf123a2d10756d4cee345d616115422e01eda493dd82cfb44abe86e8c37"]

export let checksums_aarch64: List[Str] = [
  "1dccd64c32190c78a4478f018de2b79b2e38ef6ab27bd4aefef1389c43ac1556",
  "ddefcdf123a2d10756d4cee345d616115422e01eda493dd82cfb44abe86e8c37",
]

export let checksums_x86_64: List[Str] = [
  "e514079f5f16351c2e86be96ed72967891422974d6f23e656da3e2e71cd123be",
  "ddefcdf123a2d10756d4cee345d616115422e01eda493dd82cfb44abe86e8c37",
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
