export let name: Str = "xsh"

export let ver: Str = "0.0.0"

export let rel: Str = "5"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://github.com/laputa-systems/xsh/releases/download/release-49b7a0699569c735718879e270e6e73b8f6ecc96/xsh-multicall-release-49b7a0699569c735718879e270e6e73b8f6ecc96-ARCH-linux-musl.xz => xsh-multicall",
  p"https://github.com/laputa-systems/xsh/archive/49b7a0699569c735718879e270e6e73b8f6ecc96.tar.gz => xsh-src",
]

export let checksums: List[Str] = ["SKIP", "4dafc275f2dc5d792e3ec1453c8f18f4dbd68bbaf15168b62366b610ec63fb08"]

export let checksums_aarch64: List[Str] = [
  "15c36032ddece8aa2b97cca01fcb92b1df63ac38781ac6fdfaae161e982900ff",
  "4dafc275f2dc5d792e3ec1453c8f18f4dbd68bbaf15168b62366b610ec63fb08",
]

export let checksums_x86_64: List[Str] = [
  "acfae158cd963397112775ee7462799a3b599d901848b150bce0c0fa6995512f",
  "4dafc275f2dc5d792e3ec1453c8f18f4dbd68bbaf15168b62366b610ec63fb08",
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