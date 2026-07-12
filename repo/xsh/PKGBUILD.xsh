export let name = "xsh"

export let ver = "0.0.0"

export let rel = "12"

export let deps = []

export let mkdeps_host = []

export let upstream_sources = [
  {
    source: p"https://github.com/laputa-systems/xsh/releases/download/release-5723585aa63f9d88894ca0620a5b08d4dee437d4/xsh-multicall-release-5723585aa63f9d88894ca0620a5b08d4dee437d4-ARCH-linux-musl => xsh-multicall",
    kind: "auto",
    architectures: ["all"],
    checksums: [
      {arch: "aarch64", sha256: "a5e293868a2227b0a2378ba4c43cec204cbe6819b47324f147c8aa135b8e176f"},
      {arch: "x86_64", sha256: "7519ff16d0b2b659f98de10e00a1ace65d474175a1ebef229a98f43bf85febc5"},
    ],
  },
  {
    source: p"https://github.com/laputa-systems/xsh/releases/download/release-5723585aa63f9d88894ca0620a5b08d4dee437d4/core-release-5723585aa63f9d88894ca0620a5b08d4dee437d4.tar.xz => xsh-core",
    kind: "auto",
    architectures: ["all"],
    checksums: [
      {arch: "aarch64", sha256: "ad37c386b869418a55d74a40fd4ad4179efa41300eb4ebce811fa2a554416cb9"},
      {arch: "x86_64", sha256: "ad37c386b869418a55d74a40fd4ad4179efa41300eb4ebce811fa2a554416cb9"},
    ],
  },
]

export let nostrip = true

error XshPackageError = Source(message: Str)

export let filetree = [
  {path: p"usr/bin/basename", kind: "symlink"},
  {path: p"usr/bin/cat", kind: "symlink"},
  {path: p"usr/bin/chgrp", kind: "symlink"},
  {path: p"usr/bin/chmod", kind: "symlink"},
  {path: p"usr/bin/chown", kind: "symlink"},
  {path: p"usr/bin/cp", kind: "symlink"},
  {path: p"usr/bin/cut", kind: "symlink"},
  {path: p"usr/bin/date", kind: "symlink"},
  {path: p"usr/bin/df", kind: "symlink"},
  {path: p"usr/bin/dirname", kind: "symlink"},
  {path: p"usr/bin/du", kind: "symlink"},
  {path: p"usr/bin/env", kind: "symlink"},
  {path: p"usr/bin/fd", kind: "symlink"},
  {path: p"usr/bin/fold", kind: "symlink"},
  {path: p"usr/bin/getty", kind: "symlink"},
  {path: p"usr/bin/head", kind: "symlink"},
  {path: p"usr/bin/host", kind: "symlink"},
  {path: p"usr/bin/hostname", kind: "symlink"},
  {path: p"usr/bin/ifdown", kind: "symlink"},
  {path: p"usr/bin/ifup", kind: "symlink"},
  {path: p"usr/bin/ip", kind: "symlink"},
  {path: p"usr/bin/link", kind: "symlink"},
  {path: p"usr/bin/ln", kind: "symlink"},
  {path: p"usr/bin/ls", kind: "symlink"},
  {path: p"usr/bin/mdev", kind: "symlink"},
  {path: p"usr/bin/mkdir", kind: "symlink"},
  {path: p"usr/bin/mv", kind: "symlink"},
  {path: p"usr/bin/nproc", kind: "symlink"},
  {path: p"usr/bin/passwd", kind: "symlink"},
  {path: p"usr/bin/paste", kind: "symlink"},
  {path: p"usr/bin/printenv", kind: "symlink"},
  {path: p"usr/bin/printf", kind: "symlink"},
  {path: p"usr/bin/pstree", kind: "symlink"},
  {path: p"usr/bin/pwd", kind: "symlink"},
  {path: p"usr/bin/readlink", kind: "symlink"},
  {path: p"usr/bin/realpath", kind: "symlink"},
  {path: p"usr/bin/rev", kind: "symlink"},
  {path: p"usr/bin/rg", kind: "symlink"},
  {path: p"usr/bin/rm", kind: "symlink"},
  {path: p"usr/bin/rmdir", kind: "symlink"},
  {path: p"usr/bin/seq", kind: "symlink"},
  {path: p"usr/bin/shuf", kind: "symlink"},
  {path: p"usr/bin/sort", kind: "symlink"},
  {path: p"usr/bin/split", kind: "symlink"},
  {path: p"usr/bin/stat", kind: "symlink"},
  {path: p"usr/bin/strings", kind: "symlink"},
  {path: p"usr/bin/tail", kind: "symlink"},
  {path: p"usr/bin/tar", kind: "symlink"},
  {path: p"usr/bin/tee", kind: "symlink"},
  {path: p"usr/bin/touch", kind: "symlink"},
  {path: p"usr/bin/tr", kind: "symlink"},
  {path: p"usr/bin/tree", kind: "symlink"},
  {path: p"usr/bin/uname", kind: "symlink"},
  {path: p"usr/bin/uniq", kind: "symlink"},
  {path: p"usr/bin/wc", kind: "symlink"},
  {path: p"usr/bin/which", kind: "symlink"},
  {path: p"usr/bin/sh", kind: "symlink"},
  {path: p"usr/bin/xsh", kind: "binary"},
  {path: p"usr/bin/xshi", kind: "symlink"},
  {path: p"usr/bin/xsht", kind: "symlink"},
  {path: p"usr/lib/xsh/core/basename", kind: "file"},
  {path: p"usr/lib/xsh/core/cat", kind: "file"},
  {path: p"usr/lib/xsh/core/chgrp", kind: "file"},
  {path: p"usr/lib/xsh/core/chmod", kind: "file"},
  {path: p"usr/lib/xsh/core/chown", kind: "file"},
  {path: p"usr/lib/xsh/core/cp", kind: "file"},
  {path: p"usr/lib/xsh/core/cut", kind: "file"},
  {path: p"usr/lib/xsh/core/date", kind: "file"},
  {path: p"usr/lib/xsh/core/df", kind: "file"},
  {path: p"usr/lib/xsh/core/dirname", kind: "file"},
  {path: p"usr/lib/xsh/core/du", kind: "file"},
  {path: p"usr/lib/xsh/core/env", kind: "file"},
  {path: p"usr/lib/xsh/core/fd", kind: "file"},
  {path: p"usr/lib/xsh/core/fold", kind: "file"},
  {path: p"usr/lib/xsh/core/getty", kind: "file"},
  {path: p"usr/lib/xsh/core/head", kind: "file"},
  {path: p"usr/lib/xsh/core/host", kind: "file"},
  {path: p"usr/lib/xsh/core/hostname", kind: "file"},
  {path: p"usr/lib/xsh/core/ifdown", kind: "file"},
  {path: p"usr/lib/xsh/core/ifup", kind: "file"},
  {path: p"usr/lib/xsh/core/ip", kind: "file"},
  {path: p"usr/lib/xsh/core/lib/auth", kind: "file"},
  {path: p"usr/lib/xsh/core/link", kind: "file"},
  {path: p"usr/lib/xsh/core/ln", kind: "file"},
  {path: p"usr/lib/xsh/core/ls", kind: "file"},
  {path: p"usr/lib/xsh/core/mdev", kind: "file"},
  {path: p"usr/lib/xsh/core/mkdir", kind: "file"},
  {path: p"usr/lib/xsh/core/mv", kind: "file"},
  {path: p"usr/lib/xsh/core/nproc", kind: "file"},
  {path: p"usr/lib/xsh/core/passwd", kind: "file"},
  {path: p"usr/lib/xsh/core/paste", kind: "file"},
  {path: p"usr/lib/xsh/core/printenv", kind: "file"},
  {path: p"usr/lib/xsh/core/printf", kind: "file"},
  {path: p"usr/lib/xsh/core/pstree", kind: "file"},
  {path: p"usr/lib/xsh/core/pwd", kind: "file"},
  {path: p"usr/lib/xsh/core/readlink", kind: "file"},
  {path: p"usr/lib/xsh/core/realpath", kind: "file"},
  {path: p"usr/lib/xsh/core/rev", kind: "file"},
  {path: p"usr/lib/xsh/core/rg", kind: "file"},
  {path: p"usr/lib/xsh/core/rm", kind: "file"},
  {path: p"usr/lib/xsh/core/rmdir", kind: "file"},
  {path: p"usr/lib/xsh/core/seq", kind: "file"},
  {path: p"usr/lib/xsh/core/shuf", kind: "file"},
  {path: p"usr/lib/xsh/core/sort", kind: "file"},
  {path: p"usr/lib/xsh/core/split", kind: "file"},
  {path: p"usr/lib/xsh/core/stat", kind: "file"},
  {path: p"usr/lib/xsh/core/strings", kind: "file"},
  {path: p"usr/lib/xsh/core/su", kind: "file"},
  {path: p"usr/lib/xsh/core/tail", kind: "file"},
  {path: p"usr/lib/xsh/core/tar", kind: "file"},
  {path: p"usr/lib/xsh/core/tee", kind: "file"},
  {path: p"usr/lib/xsh/core/touch", kind: "file"},
  {path: p"usr/lib/xsh/core/tr", kind: "file"},
  {path: p"usr/lib/xsh/core/tree", kind: "file"},
  {path: p"usr/lib/xsh/core/uname", kind: "file"},
  {path: p"usr/lib/xsh/core/uniq", kind: "file"},
  {path: p"usr/lib/xsh/core/wc", kind: "file"},
  {path: p"usr/lib/xsh/core/which", kind: "file"},
]

export proc build(dest: Path) [fs, error] {
  let staged = fs.children(p"xsh-multicall")? |> where .kind == "file"

  if staged.len() != 1 {
    return Err(XshPackageError.Source("expected one staged xsh multicall release artifact"))
  }

  fs.mkdir(fp"${dest}/usr/bin")?
  fs.install(staged[0].path, fp"${dest}/usr/bin/xsh", 0o755, parents: true, overwrite: true)?

  for command_name in ["sh", "xshi", "xsht"] {
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

  for entry in fs.children(p"xsh-core")? |> where .kind == "file" and .name != "su" {
    fs.symlink(fp"../lib/xsh/core/${entry.name}", fp"${dest}/usr/bin/${entry.name}")?
  }
}

export proc pre_install(root: Path) [fs, error] {
  for command_name in ["sh", "xsh", "xshi", "xsht"] {
    fs.remove(fp"${root}/bin/${command_name}", missing_ok: true)?
    fs.remove(fp"${root}/usr/bin/${command_name}", missing_ok: true)?
    fs.remove(fp"${root}/usr/local/bin/${command_name}", missing_ok: true)?
  }

  if fs.exists(fp"${root}/usr/lib/xsh/core")? {
    for entry in fs.children(fp"${root}/usr/lib/xsh/core")? |> where .kind == "file" and .name != "su" {
      fs.remove(fp"${root}/usr/bin/${entry.name}", missing_ok: true)?
    }
  }
}
