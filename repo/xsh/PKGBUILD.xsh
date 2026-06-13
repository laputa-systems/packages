export let name: Str = "xsh"

export let ver: Str = "release-670160dd24643af6c56ed96f232741e14fbc25b7"

export let rel: Str = "3"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://github.com/laputa-systems/xsh/releases/download/VERSION/xsh-multicall-VERSION-ARCH-linux-musl.xz => xsh-multicall",
  p"https://github.com/laputa-systems/xsh/archive/670160dd24643af6c56ed96f232741e14fbc25b7.tar.gz => xsh-src",
]

export let checksums: List[Str] = ["SKIP", "1f64983f7278ccc3755163a78c94eab18b90d1ef5e828b8514598f4604dbae30"]

export let checksums_aarch64: List[Str] = [
  "a65d7a6d8c673af38c233b2c4e982b61a413ded36fd198b84ee8a6f39e7a41d6",
  "1f64983f7278ccc3755163a78c94eab18b90d1ef5e828b8514598f4604dbae30",
]

export let checksums_x86_64: List[Str] = [
  "5a318f617c0b842fa729a74af59aa0c07b3b5cb7b8d8e5c61e0993d3fe300a4c",
  "1f64983f7278ccc3755163a78c94eab18b90d1ef5e828b8514598f4604dbae30",
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
