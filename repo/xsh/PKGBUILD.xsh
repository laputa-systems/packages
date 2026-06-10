export let name: Str = "xsh"

export let ver: Str = "release-f9034b48f96f49f42914498cd7bbe8a080b945b3"

export let rel: Str = "3"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://laputa.17166969.xyz/packages/ARCH/xsh/xsh-VERSION-2.tar.gz => xsh-package",
  p"https://github.com/laputa-systems/xsh/archive/f9034b48f96f49f42914498cd7bbe8a080b945b3.tar.gz => xsh-src",
]

export let checksums: List[Str] = ["SKIP", "83abe51d669bf6e9f52c47c4b86bb7101136ba1955181ed094b59b4baa55c625"]

export let checksums_aarch64: List[Str] = [
  "51884dd28bc8ac2d62e7639ca9d8307c6eb0b0b325c31771c43b5f0a73fa2d8a",
  "83abe51d669bf6e9f52c47c4b86bb7101136ba1955181ed094b59b4baa55c625",
]

export let checksums_x86_64: List[Str] = [
  "963bf3e1b80a774919b7776905140bb4a58081cb4f8692f11efaa982c9e895d5",
  "83abe51d669bf6e9f52c47c4b86bb7101136ba1955181ed094b59b4baa55c625",
]

export let nostrip: Bool = true

error XshPackageError = Source(message: Str)

export proc process_sources(src: Path) [fs, process, env, error] {
  if ! fs.exists(fp"${src}/xsh-package/usr/local/bin/xsh")? {
    return Err(XshPackageError.Source("expected staged xsh package tree"))
  }
}

export proc build(dest: Path) [fs, error] {
  for command_name in ["xsh", "xshi", "xsht"] {
    fs.install(
      fp"xsh-package/usr/local/bin/${command_name}",
      fp"${dest}/usr/local/bin/${command_name}",
      0o755,
      parents: true,
      overwrite: true,
    )?
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

  fs.write(
    fp"${dest}/usr/bin/sh",
    """#!/usr/local/bin/xsh
run /usr/local/bin/xshi @args ?
""",
  )?
  fs.chmod(fp"${dest}/usr/bin/sh", 0o755)?
}

export proc pre_install(root: Path) [fs, error] {
  fs.remove(fp"${root}/usr/local/bin/xsh-multicall", missing_ok: true)?

  for command_name in ["xsh", "xshi", "xsht"] {
    fs.remove(fp"${root}/usr/local/bin/${command_name}", missing_ok: true)?
  }
}
