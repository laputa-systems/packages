export let name = "xsh"

export let ver = "0.0.0"

export let rel = "10"

export let deps = []

export let mkdeps = []

export let sources = [
  p"https://github.com/laputa-systems/xsh/releases/download/release-42b26e0f97a7c15c0ad9cf611a0c09e9cb4ca21b/xsh-multicall-release-42b26e0f97a7c15c0ad9cf611a0c09e9cb4ca21b-ARCH-linux-musl => xsh-multicall",
  p"https://github.com/laputa-systems/xsh/releases/download/release-42b26e0f97a7c15c0ad9cf611a0c09e9cb4ca21b/core-release-42b26e0f97a7c15c0ad9cf611a0c09e9cb4ca21b.tar.xz => xsh-core",
]

export let checksums = ["SKIP", "0bae60ddb8e15a2f03f81ccf4e5ad69e6ed2215d656ea6a6395a24d1e86dcdeb"]

export let checksums_aarch64 = [
  "2f442944de1caf82a52d725b86326e2fa41748eb0dffbeae9a444b6547cb4e0e",
  "fa6bf4212677387f4d6a97e95b13cf9b6793f4296ad1cb561357dacab039c111",
]

export let checksums_x86_64 = [
  "af98604c18515c9a7ee6b9e598c5fb87aa9c8ed9490eda8e6c56f1c15daa5328",
  "fa6bf4212677387f4d6a97e95b13cf9b6793f4296ad1cb561357dacab039c111",
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