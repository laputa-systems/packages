export let name: Str = "xsh"

export let ver: Str = "0.0.0"

export let rel: Str = "1"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://github.com/laputa-systems/xsh/releases/download/release-f61ac8c2d07cecdc7057f96558e14dd636f4c819/xsh-multicall-release-f61ac8c2d07cecdc7057f96558e14dd636f4c819-ARCH-linux-musl.xz => xsh-multicall",
  p"https://github.com/laputa-systems/xsh/archive/f61ac8c2d07cecdc7057f96558e14dd636f4c819.tar.gz => xsh-src",
]

export let checksums: List[Str] = ["SKIP", "e0e5a8a5d9e802662827544daf589bb05311d594d1def9608b51c6a6e0b494ec"]

export let checksums_aarch64: List[Str] = [
  "d66429298908faec83636b335f238c42467742d5a688d2543c4c3a3a4b109208",
  "e0e5a8a5d9e802662827544daf589bb05311d594d1def9608b51c6a6e0b494ec",
]

export let checksums_x86_64: List[Str] = [
  "bc0a03f090ef6dce1c3724b782e8f7eda359d2b14d69ed7882a8941df8bcd9b1",
  "e0e5a8a5d9e802662827544daf589bb05311d594d1def9608b51c6a6e0b494ec",
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
