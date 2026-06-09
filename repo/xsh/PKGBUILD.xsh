export let name: Str = "xsh"

export let ver: Str = "release-d9d48a1c79aed3d2891014acb175284b6993bc52"

export let rel: Str = "2"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://github.com/laputa-systems/xsh/releases/download/VERSION/xsh-multicall-VERSION-ARCH-linux-musl.xz => xsh-multicall",
  p"https://github.com/laputa-systems/xsh/archive/d9d48a1c79aed3d2891014acb175284b6993bc52.tar.gz => xsh-src",
]

export let checksums: List[Str] = ["SKIP", "58aec0a39887e9f9220b001f8ce59561e26f0ab1262c0353d79ad5f6d780760b"]

export let checksums_aarch64: List[Str] = [
  "14e66fb85e4971441a193adb96d4cb8bf2158e48d95e7952a5b7874d1284be29",
  "58aec0a39887e9f9220b001f8ce59561e26f0ab1262c0353d79ad5f6d780760b",
]

export let checksums_x86_64: List[Str] = [
  "cb86e7537e32915b245c92e01434d465a936cd807c46c9bbe644818a55b07e49",
  "58aec0a39887e9f9220b001f8ce59561e26f0ab1262c0353d79ad5f6d780760b",
]

export let nostrip: Bool = true

error XshPackageError = Source(message: Str)

export proc process_sources(src: Path) [fs, process, env, error] {
  let candidates = fs.files(fp"${src}/xsh-multicall", gitignore: false) |> where .ext == "xz"

  if candidates.len() != 1 {
    return Err(XshPackageError.Source("expected one xsh-multicall .xz source"))
  }

  fs.remove(fp"${src}/xsh-multicall/xsh-multicall", missing_ok: true)?
  archive.decompress(candidates[0].path, fp"${src}/xsh-multicall/xsh-multicall")?
  fp"${src}/xsh-multicall/xsh-multicall".chmod(0o755)?
}

export proc build(dest: Path) [fs, error] {
  fs.install(
    p"xsh-multicall/xsh-multicall",
    fp"${dest}/usr/local/bin/xsh-multicall",
    0o755,
    parents: true,
    overwrite: true,
  )?

  for command_name in ["xsh", "xshi", "xsht"] {
    fs.remove(fp"${dest}/usr/local/bin/${command_name}", missing_ok: true)?
    fs.symlink(p"xsh-multicall", fp"${dest}/usr/local/bin/${command_name}")?
  }

  let _ = fs.copy_tree(p"xsh-src/core", fp"${dest}/usr/lib/xsh/core", parents: true, overwrite: true)?
  fs.remove(fp"${dest}/usr/lib/xsh/core/xinit.xsh", missing_ok: true)?

  for entry in fs.walk(fp"${dest}/usr/lib/xsh/core", gitignore: false)? |> where .kind == "file" and .ext == "xsh" {
    fs.chmod(entry.path, 0o755)?
  }

  fs.mkdir(fp"${dest}/usr/bin")?

  for entry in fs.children(fp"${dest}/usr/lib/xsh/core")? {
    if entry.kind == "file" and entry.name.ends_with(".xsh") {
      let command_name = entry.name.replace(".xsh", "")
      let link = fp"${dest}/usr/bin/${command_name}"
      fs.remove(link, missing_ok: true)?
      fs.symlink(fp"../lib/xsh/core/${entry.name}", link)?
    }
  }

  fs.remove(fp"${dest}/usr/bin/sh", missing_ok: true)?
  fs.symlink(p"../local/bin/xshi", fp"${dest}/usr/bin/sh")?
}
