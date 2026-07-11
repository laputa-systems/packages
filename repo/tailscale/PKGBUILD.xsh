export let name = "tailscale"

export let ver = "1.96.4"

export let rel = "11"

export let deps = ["iptables", "xinit"]

export let mkdeps = ["llvm-toolchain"]

export let sources = [p"https://pkgs.tailscale.com/stable/tailscale_VERSION_GOARCH.tgz", p"service.xsh"]

export let checksums = ["SKIP", "SKIP"]

export let checksums_aarch64 = [
  "a27249bc70d7b37a68f8be7f5c4507ea5f354e592dce43cb5d4f3e742b313c3c",
  "SKIP",
]

export let checksums_x86_64 = [
  "a1cba18826b1f91cb25ef7f5b8259b5258339b42db7867af9269e21829ea78cc",
  "SKIP",
]

export proc build(dest: Path) [fs, process, error] {
  let strip = process.which("llvm-strip")?
  run $strip "--strip-all" p"tailscale" p"tailscaled" ?

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
