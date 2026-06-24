export let name: Str = "xsh"

export let ver: Str = "0.0.0"

export let rel: Str = "3"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://github.com/laputa-systems/xsh/releases/download/release-81e1dff8ab048f3b011eda3e8a276c78cea2bb66/xsh-multicall-release-81e1dff8ab048f3b011eda3e8a276c78cea2bb66-ARCH-linux-musl.xz => xsh-multicall",
  p"https://github.com/laputa-systems/xsh/archive/81e1dff8ab048f3b011eda3e8a276c78cea2bb66.tar.gz => xsh-src",
]

export let checksums: List[Str] = ["SKIP", "8eaa6f12175a7bc1f63e35b4965fc2c885967434ab67bba5ceee06ae27508295"]

export let checksums_aarch64: List[Str] = [
  "bbe1c2c2a0b2d6a5dad438065715afb375a9c44fe9b105a81e5f3ecdd2a2c3b2",
  "8eaa6f12175a7bc1f63e35b4965fc2c885967434ab67bba5ceee06ae27508295",
]

export let checksums_x86_64: List[Str] = [
  "b5552e9f12fd690287aa21fed13f2eee1246407b6c52f1c4f919a92bc08294c4",
  "8eaa6f12175a7bc1f63e35b4965fc2c885967434ab67bba5ceee06ae27508295",
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