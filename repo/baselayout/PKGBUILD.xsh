##! XSH module `PKGBUILD` package and build operations.
export let name = "baselayout"

## Exported declaration `ver`.
export let ver = "1"

## Exported declaration `rel`.
export let rel = "14"

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

## Exported declaration `extract_install`.
export let extract_install = true

## Exported declaration `filetree`.
export let filetree = [
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

  for keep in fs.walk(dest) |> where .kind == "file" and .name == ".keep" {
    keep.path.remove()?
  }
}
