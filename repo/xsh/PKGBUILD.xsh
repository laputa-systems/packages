export let name: Str = "xsh"

export let ver: Str = "0.0.0"

export let rel: Str = "6"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://github.com/laputa-systems/xsh/releases/download/release-dbeacac33697faa06b47633108d144297f54f798/xsh-multicall-release-dbeacac33697faa06b47633108d144297f54f798-ARCH-linux-musl.xz => xsh-multicall",
  p"https://github.com/laputa-systems/xsh/archive/dbeacac33697faa06b47633108d144297f54f798.tar.gz => xsh-src",
]

export let checksums: List[Str] = ["SKIP", "04f3cbad26e9d6431ba06d481f789a236a3923eb594144a485aca16d6ab6f90c"]

export let checksums_aarch64: List[Str] = [
  "f7afb27dc8cb340b8dedf332f649fd58cc2f15c7617cd4a67b19677b1fdedaa7",
  "04f3cbad26e9d6431ba06d481f789a236a3923eb594144a485aca16d6ab6f90c",
]

export let checksums_x86_64: List[Str] = [
  "dc958ada6a5418c197eb2aae2a95a9a63299382fc994611f41b38903c19d1761",
  "04f3cbad26e9d6431ba06d481f789a236a3923eb594144a485aca16d6ab6f90c",
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