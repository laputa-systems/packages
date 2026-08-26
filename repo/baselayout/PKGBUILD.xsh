##! XSH module `PKGBUILD` package and build operations.
## Package recipe export.
export let name = "baselayout"

## Explicit payload or metapackage classification.
export let package_kind = "payload"

## Exported declaration `ver`.
export let ver = "1"

## Exported declaration `rel`.
export let rel = "15"

## Exported declaration `deps`.
export let deps = []

## Exported declaration `mkdeps_host`.
export let mkdeps_host = []

## Exported declaration `upstream_sources`.
export let upstream_sources = [
  {
    source: p"files/rootfs",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "SKIP",
      },
    ],
  },
]

## Exported declaration `filetree`.
## Empty mount and state directories are payload, not ambient host state. In
## particular, the kernel mounts devtmpfs before PID 1 can create /dev.
export let filetree = [
  {path: p"boot", kind: "tree"},
  {path: p"dev", kind: "tree"},
  {path: p"dev/pts", kind: "tree"},
  {path: p"dev/shm", kind: "tree"},
  {path: p"etc/rc.d", kind: "tree"},
  {path: p"mnt", kind: "tree"},
  {path: p"opt", kind: "tree"},
  {path: p"proc", kind: "tree"},
  {path: p"root", kind: "tree"},
  {path: p"run", kind: "tree"},
  {path: p"sys", kind: "tree"},
  {path: p"tmp", kind: "tree"},
  {path: p"usr/include", kind: "tree"},
  {path: p"usr/lib/init/rc.d", kind: "tree"},
  {path: p"usr/local/bin", kind: "tree"},
  {path: p"usr/share", kind: "tree"},
  {path: p"var/cache", kind: "tree"},
  {path: p"var/empty", kind: "tree"},
  {path: p"var/lib/init", kind: "tree"},
  {path: p"var/local", kind: "tree"},
  {path: p"var/log", kind: "tree"},
  {path: p"var/opt", kind: "tree"},
  {path: p"var/spool/mail", kind: "tree"},
  {path: p"var/tmp", kind: "tree"},
  {
    path: p"bin",
    kind: "symlink",
  },
  {
    path: p"etc/environment",
    kind: "file",
  },
  {
    path: p"etc/fstab",
    kind: "file",
  },
  {
    path: p"etc/group",
    kind: "file",
  },
  {
    path: p"etc/hosts",
    kind: "file",
  },
  {
    path: p"etc/inittab",
    kind: "file",
  },
  {
    path: p"etc/mdev.conf",
    kind: "file",
  },
  {
    path: p"etc/mtab",
    kind: "symlink",
  },
  {
    path: p"etc/os-release",
    kind: "file",
  },
  {
    path: p"etc/passwd",
    kind: "file",
  },
  {
    path: p"etc/profile",
    kind: "file",
  },
  {
    path: p"etc/shadow",
    kind: "file",
  },
  {
    path: p"etc/shells",
    kind: "file",
  },
  {
    path: p"etc/sudoers",
    kind: "file",
  },
  {
    path: p"lib",
    kind: "symlink",
  },
  {
    path: p"lib64",
    kind: "symlink",
  },
  {
    path: p"sbin",
    kind: "symlink",
  },
  {
    path: p"usr/bin/getent",
    kind: "file",
  },
  {
    path: p"usr/lib/init/mdev.supervise",
    kind: "file",
  },
  {
    path: p"usr/lib/init/rc.boot",
    kind: "file",
  },
  {
    path: p"usr/lib/init/rc.shutdown",
    kind: "file",
  },
  {
    path: p"usr/lib64",
    kind: "symlink",
  },
  {
    path: p"usr/sbin",
    kind: "symlink",
  },
  {
    path: p"var/lock",
    kind: "symlink",
  },
  {
    path: p"var/mail",
    kind: "symlink",
  },
  {
    path: p"var/run",
    kind: "symlink",
  },
]

## Exported declaration `build`.
export proc build(dest: Path) [fs, error] {
  let _ = fs.copy_tree(p".", dest, parents: true, overwrite: true)?

  # `copy_tree` need not retain an otherwise empty source directory. Materialize
  # every declared base-layout directory before removing its `.keep` marker, so
  # the immutable payload archives the boot mountpoints.
  for tree in [
    "boot",
    "dev",
    "dev/pts",
    "dev/shm",
    "etc/rc.d",
    "mnt",
    "opt",
    "proc",
    "root",
    "run",
    "sys",
    "tmp",
    "usr/include",
    "usr/lib/init/rc.d",
    "usr/local/bin",
    "usr/share",
    "var/cache",
    "var/empty",
    "var/lib/init",
    "var/local",
    "var/log",
    "var/opt",
    "var/spool/mail",
    "var/tmp",
  ] {
    fs.mkdir(fp"${dest}/${tree}")?
  }

  # `.keep` is hidden, so it must be visible to the cleanup walk. Leaving it
  # behind makes every declared directory non-empty and drops the real
  # mountpoint from the immutable archive.
  for keep in fs.walk(dest, hidden: true) |> where .kind == "file" and .name == ".keep" {
    keep.path.remove()?
  }
}
