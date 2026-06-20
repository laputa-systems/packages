export let name: Str = "xsh"

export let ver: Str = "0.0.0"

export let rel: Str = "2"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://github.com/laputa-systems/xsh/releases/download/release-eff39099d6f8a20f67328512f30d5727405d7d16/xsh-multicall-release-eff39099d6f8a20f67328512f30d5727405d7d16-ARCH-linux-musl.xz => xsh-multicall",
  p"https://github.com/laputa-systems/xsh/archive/eff39099d6f8a20f67328512f30d5727405d7d16.tar.gz => xsh-src",
]

export let checksums: List[Str] = ["SKIP", "ec64a76c4732b4b1e7448de8a33c034144bf9b2832c55c458d9671a4c1073ed3"]

export let checksums_aarch64: List[Str] = [
  "451828d99307ad4c7281dcdb9b2126dee912602e088aa58d4e52d73d2b60f243",
  "ec64a76c4732b4b1e7448de8a33c034144bf9b2832c55c458d9671a4c1073ed3",
]

export let checksums_x86_64: List[Str] = [
  "b84e4fdb5c76fbaace754e5c23182c90a82924893be158df2bdf32f485e09d21",
  "ec64a76c4732b4b1e7448de8a33c034144bf9b2832c55c458d9671a4c1073ed3",
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