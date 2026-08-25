##! Package recipe metadata and build operations.
## Package recipe export.
export let name = "xsh"

## Explicit payload or metapackage classification.
export let package_kind = "payload"

## Package recipe export.
export let ver = "0.0.0"

## Package recipe export.
export let rel = "14"

## Package recipe export.
export let deps = []

## Package recipe export.
export let mkdeps_host = []

## Package recipe export.
export let upstream_sources = [
  {
    source: p"https://github.com/laputa-systems/xsh/releases/download/release-d09c6c3305ab8c650043bd8d32e03f2db6509e97/xsh-release-d09c6c3305ab8c650043bd8d32e03f2db6509e97-ARCH-linux-musl => xsh-bin",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "aarch64",
        sha256: "bc9117b8ac70c726002835e7ab1eaff0d45ede7b067bc85ddba7971eb8b8ffbb",
      },
      {
        arch: "x86_64",
        sha256: "03e190c8ee15020b04b27e2066a7e53665452c9dce821bd0af80378ef664c746",
      },
    ],
  },
  {
    source: p"https://github.com/laputa-systems/xsh/releases/download/release-d09c6c3305ab8c650043bd8d32e03f2db6509e97/xshi-release-d09c6c3305ab8c650043bd8d32e03f2db6509e97-ARCH-linux-musl => xshi-bin",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "aarch64",
        sha256: "5cf2f028fd0f0e6cbae213d7037e28e1aa92ca74768c5fce5e300d9725014bb6",
      },
      {
        arch: "x86_64",
        sha256: "897b22cae065625179f8b2cb18c48828464eb1cd135f32da0e9358b237f3e195",
      },
    ],
  },
  {
    source: p"https://github.com/laputa-systems/xsh/releases/download/release-d09c6c3305ab8c650043bd8d32e03f2db6509e97/xsht-release-d09c6c3305ab8c650043bd8d32e03f2db6509e97-ARCH-linux-musl => xsht-bin",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "aarch64",
        sha256: "86c2d1ac329702c0def779adb47640f84cdda9466630e2c98681750fc037a2e2",
      },
      {
        arch: "x86_64",
        sha256: "83ea617d6fc1a9f9e7908b292d51d8b263df15904d67d17b7c7f04d825a98a20",
      },
    ],
  },
  {
    source: p"https://github.com/laputa-systems/xsh/releases/download/release-d09c6c3305ab8c650043bd8d32e03f2db6509e97/core-release-d09c6c3305ab8c650043bd8d32e03f2db6509e97.tar.xz => xsh-core",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "aarch64",
        sha256: "7040377b294b165fde676f6b808d32ee5d5dc0f2cc84dd6d1350974d22989c95",
      },
      {
        arch: "x86_64",
        sha256: "7040377b294b165fde676f6b808d32ee5d5dc0f2cc84dd6d1350974d22989c95",
      },
    ],
  },
]

## Package recipe export.
export let nostrip = true

error XshPackageError = Source(message: Str)

## Package recipe export.
export let filetree = [
  {
    path: p"usr/bin/basename",
    kind: "symlink",
  },
  {
    path: p"usr/bin/cat",
    kind: "symlink",
  },
  {
    path: p"usr/bin/chgrp",
    kind: "symlink",
  },
  {
    path: p"usr/bin/chmod",
    kind: "symlink",
  },
  {
    path: p"usr/bin/chown",
    kind: "symlink",
  },
  {
    path: p"usr/bin/cp",
    kind: "symlink",
  },
  {
    path: p"usr/bin/cut",
    kind: "symlink",
  },
  {
    path: p"usr/bin/date",
    kind: "symlink",
  },
  {
    path: p"usr/bin/df",
    kind: "symlink",
  },
  {
    path: p"usr/bin/dirname",
    kind: "symlink",
  },
  {
    path: p"usr/bin/du",
    kind: "symlink",
  },
  {
    path: p"usr/bin/env",
    kind: "symlink",
  },
  {
    path: p"usr/bin/fd",
    kind: "symlink",
  },
  {
    path: p"usr/bin/fold",
    kind: "symlink",
  },
  {
    path: p"usr/bin/getty",
    kind: "symlink",
  },
  {
    path: p"usr/bin/head",
    kind: "symlink",
  },
  {
    path: p"usr/bin/host",
    kind: "symlink",
  },
  {
    path: p"usr/bin/hostname",
    kind: "symlink",
  },
  {
    path: p"usr/bin/ifdown",
    kind: "symlink",
  },
  {
    path: p"usr/bin/ifup",
    kind: "symlink",
  },
  {
    path: p"usr/bin/ip",
    kind: "symlink",
  },
  {
    path: p"usr/bin/link",
    kind: "symlink",
  },
  {
    path: p"usr/bin/ln",
    kind: "symlink",
  },
  {
    path: p"usr/bin/ls",
    kind: "symlink",
  },
  {
    path: p"usr/bin/mdev",
    kind: "symlink",
  },
  {
    path: p"usr/bin/mkdir",
    kind: "symlink",
  },
  {
    path: p"usr/bin/mv",
    kind: "symlink",
  },
  {
    path: p"usr/bin/nproc",
    kind: "symlink",
  },
  {
    path: p"usr/bin/passwd",
    kind: "symlink",
  },
  {
    path: p"usr/bin/paste",
    kind: "symlink",
  },
  {
    path: p"usr/bin/printenv",
    kind: "symlink",
  },
  {
    path: p"usr/bin/printf",
    kind: "symlink",
  },
  {
    path: p"usr/bin/pstree",
    kind: "symlink",
  },
  {
    path: p"usr/bin/pwd",
    kind: "symlink",
  },
  {
    path: p"usr/bin/readlink",
    kind: "symlink",
  },
  {
    path: p"usr/bin/realpath",
    kind: "symlink",
  },
  {
    path: p"usr/bin/rev",
    kind: "symlink",
  },
  {
    path: p"usr/bin/rg",
    kind: "symlink",
  },
  {
    path: p"usr/bin/rm",
    kind: "symlink",
  },
  {
    path: p"usr/bin/rmdir",
    kind: "symlink",
  },
  {
    path: p"usr/bin/seq",
    kind: "symlink",
  },
  {
    path: p"usr/bin/shuf",
    kind: "symlink",
  },
  {
    path: p"usr/bin/sort",
    kind: "symlink",
  },
  {
    path: p"usr/bin/split",
    kind: "symlink",
  },
  {
    path: p"usr/bin/stat",
    kind: "symlink",
  },
  {
    path: p"usr/bin/strings",
    kind: "symlink",
  },
  {
    path: p"usr/bin/tail",
    kind: "symlink",
  },
  {
    path: p"usr/bin/tar",
    kind: "symlink",
  },
  {
    path: p"usr/bin/tee",
    kind: "symlink",
  },
  {
    path: p"usr/bin/touch",
    kind: "symlink",
  },
  {
    path: p"usr/bin/tr",
    kind: "symlink",
  },
  {
    path: p"usr/bin/tree",
    kind: "symlink",
  },
  {
    path: p"usr/bin/uname",
    kind: "symlink",
  },
  {
    path: p"usr/bin/uniq",
    kind: "symlink",
  },
  {
    path: p"usr/bin/wc",
    kind: "symlink",
  },
  {
    path: p"usr/bin/which",
    kind: "symlink",
  },
  {
    path: p"usr/bin/sh",
    kind: "symlink",
  },
  {
    path: p"usr/bin/xsh",
    kind: "binary",
  },
  {
    path: p"usr/bin/xshi",
    kind: "binary",
  },
  {
    path: p"usr/bin/xsht",
    kind: "binary",
  },
  {
    path: p"usr/lib/xsh/core/basename",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/cat",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/chgrp",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/chmod",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/chown",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/cp",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/cut",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/date",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/df",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/dirname",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/du",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/env",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/fd",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/fold",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/getty",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/head",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/host",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/hostname",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/ifdown",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/ifup",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/ip",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/lib/auth",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/link",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/ln",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/ls",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/mdev",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/mkdir",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/mv",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/nproc",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/passwd",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/paste",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/printenv",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/printf",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/pstree",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/pwd",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/readlink",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/realpath",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/rev",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/rg",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/rm",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/rmdir",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/seq",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/shuf",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/sort",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/split",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/stat",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/strings",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/su",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/tail",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/tar",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/tee",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/touch",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/tr",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/tree",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/uname",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/uniq",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/wc",
    kind: "file",
  },
  {
    path: p"usr/lib/xsh/core/which",
    kind: "file",
  },
]

## Package recipe export.
## Immutable root preflight now owns collision detection, so the former live-root
## Former live-root deletion is intentionally not part of this payload build.
export proc build(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/usr/bin")?
  for pair in [
    {
      source: "xsh-bin",
      dest: "xsh",
    },
    {
      source: "xshi-bin",
      dest: "xshi",
    },
    {
      source: "xsht-bin",
      dest: "xsht",
    },
  ] {
    let staged = fs.children(fp"${pair.source}")? |> where .kind == "file"
    if staged.len() != 1 {
      return Err(XshPackageError.Source(f"expected one staged ${pair.source} release artifact"))
    }

    fs.install(staged[0].path, fp"${dest}/usr/bin/${pair.dest}", 0o755, parents: true, overwrite: true)?
  }

  let shell = fp"${dest}/usr/bin/sh"
  fs.remove(shell, missing_ok: true)?
  fs.symlink(p"xshi", shell)?

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
