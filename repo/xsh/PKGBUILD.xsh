export let name = "xsh"

export let ver = "0.0.0"

export let rel = "10"

export let deps = []

export let mkdeps = []

export let sources = [
  p"https://github.com/laputa-systems/xsh/releases/download/release-181ec3af0a80b8b67c7f8e9607885b2ce621b9b1/xsh-multicall-release-181ec3af0a80b8b67c7f8e9607885b2ce621b9b1-ARCH-linux-musl => xsh-multicall",
  p"https://github.com/laputa-systems/xsh/releases/download/release-181ec3af0a80b8b67c7f8e9607885b2ce621b9b1/core-release-181ec3af0a80b8b67c7f8e9607885b2ce621b9b1.tar.xz => xsh-core",
]

export let checksums = ["SKIP", "0bae60ddb8e15a2f03f81ccf4e5ad69e6ed2215d656ea6a6395a24d1e86dcdeb"]

export let checksums_aarch64 = [
  "717191f245a589f894a5ccb14548b7e38bd4c51e15c879db2b203a09997c10ce",
  "1e5b81d715f56df3c3d98ab5eaaa372e37e8ef8af3308b57a547b2b9f24a4636",
]

export let checksums_x86_64 = [
  "b250c7ae0d9ecafb20fa28936b09588186d6458d7d97bcbe001f493d5836846d",
  "1e5b81d715f56df3c3d98ab5eaaa372e37e8ef8af3308b57a547b2b9f24a4636",
]

export let nostrip = true

error XshPackageError = Source(message: Str)

export proc build(dest: Path) [fs, error] {
  let staged = fs.children(p"xsh-multicall")? |> where .kind == "file"

  if staged.len() != 1 {
    return Err(XshPackageError.Source("expected one staged xsh multicall release artifact"))
  }

  fs.install(staged[0].path, fp"${dest}/usr/bin/xsh", 0o755, parents: true, overwrite: true)?

  for command_name in ["xshi", "xsht"] {
    let link = fp"${dest}/usr/bin/${command_name}"
    fs.remove(link, missing_ok: true)?
    fs.symlink(p"xsh", link)?
  }

  let _ = fs.copy_tree(p"xsh-core", fp"${dest}/usr/lib/xsh/core", parents: true, overwrite: true)?

  for entry in fs.walk(fp"${dest}/usr/lib/xsh/core", gitignore: false)? |> where .kind == "file" {
    let text = fs.read_text(entry.path)?
    let normalized = text.replace("#!/usr/local/bin/xsh", "#!/bin/xsh").replace("#!/usr/bin/env -S xsh", "#!/bin/xsh")
    fs.write(entry.path, normalized)?
    fs.chmod(entry.path, 0o755)?
  }

  fs.mkdir(fp"${dest}/usr/bin")?

  for entry in fs.children(p"xsh-core")? |> where .kind == "file" and .name != "su" {
    fs.symlink(fp"../lib/xsh/core/${entry.name}", fp"${dest}/usr/bin/${entry.name}")?
  }
}

export proc pre_install(root: Path) [fs, error] {
  for command_name in ["xsh", "xshi", "xsht"] {
    fs.remove(fp"${root}/usr/bin/${command_name}", missing_ok: true)?
    fs.remove(fp"${root}/usr/local/bin/${command_name}", missing_ok: true)?
  }

  if fs.exists(fp"${root}/usr/lib/xsh/core")? {
    for entry in fs.children(fp"${root}/usr/lib/xsh/core")? |> where .kind == "file" and .name != "su" {
      fs.remove(fp"${root}/usr/bin/${entry.name}", missing_ok: true)?
    }
  }
}
