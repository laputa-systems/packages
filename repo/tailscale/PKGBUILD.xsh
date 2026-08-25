##! Package recipe metadata and build operations.
## Package recipe export.
export let name = "tailscale"

## Explicit payload or metapackage classification.
export let package_kind = "payload"

## Package recipe export.
export let ver = "1.96.4"

## Package recipe export.
export let rel = "12"

## Package recipe export.
export let deps = ["iptables", "xinit"]

## Package recipe export.
export let mkdeps_host = ["llvm-toolchain"]

## Package recipe export.
export let upstream_sources = [
  {
    source: p"https://pkgs.tailscale.com/stable/tailscale_VERSION_GOARCH.tgz",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "aarch64",
        sha256: "a27249bc70d7b37a68f8be7f5c4507ea5f354e592dce43cb5d4f3e742b313c3c",
      },
      {
        arch: "x86_64",
        sha256: "a1cba18826b1f91cb25ef7f5b8259b5258339b42db7867af9269e21829ea78cc",
      },
    ],
  },
  {
    source: p"service.xsh",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "aarch64",
        sha256: "SKIP",
      },
      {
        arch: "x86_64",
        sha256: "SKIP",
      },
    ],
  },
]

## Package recipe export.
export let filetree = [
  {
    path: p"usr/bin/tailscale",
    kind: "binary",
  },
  {
    path: p"usr/bin/tailscaled",
    kind: "binary",
  },
  {
    path: p"usr/lib/sysctl.d/50-tailscale-ipv6.conf",
    kind: "file",
  },
  {
    path: p"usr/lib/xinit/services/tailscaled.xsh",
    kind: "file",
  },
]

## Package recipe export.
export proc build(dest: Path) [fs, error] {
  fs.install(p"tailscale", fp"${dest}/usr/bin/tailscale", 0o755, parents: true, overwrite: true)?
  fs.install(p"tailscaled", fp"${dest}/usr/bin/tailscaled", 0o755, parents: true, overwrite: true)?
  fs.install(p"service.xsh", fp"${dest}/usr/lib/xinit/services/tailscaled.xsh", 0o644, parents: true, overwrite: true)?

  # Persistent state survives reboots on the root filesystem.
  fs.mkdir(fp"${dest}/var/lib/tailscale")?
  fs.mkdir(fp"${dest}/usr/lib/sysctl.d")?

  fs.write(
    fp"${dest}/usr/lib/sysctl.d/50-tailscale-ipv6.conf",
    """net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
""",
  )?
}
