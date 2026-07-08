export let name: Str = "laputa-net"

export let ver: Str = "1"

export let rel: Str = "8"

# ifup/ifdown are xsh core applets; the net service drives them.
# wpa_supplicant provides Wi-Fi association for wireless interfaces.
export let deps: List[Str] = ["xsh", "wpa_supplicant"]

export let mkdeps: List[Str] = ["xinit"]

export let sources: List[Path] = [p"service.xsh", p"interfaces"]

export let checksums: List[Str] = ["SKIP", "SKIP"]

export proc build(dest: Path) [fs, error] {
  fs.install(p"service.xsh", fp"${dest}/usr/lib/xinit/services/net.xsh", 0o644, parents: true, overwrite: true)?
  fs.install(p"interfaces", fp"${dest}/etc/network/interfaces", 0o644, parents: true, overwrite: true)?
  fs.mkdir(fp"${dest}/etc/network/if-pre-up.d")?
  fs.mkdir(fp"${dest}/etc/network/if-up.d")?
  fs.mkdir(fp"${dest}/etc/network/if-down.d")?
  fs.mkdir(fp"${dest}/etc/network/if-pre-down.d")?
  fs.mkdir(fp"${dest}/etc/network/if-post-down.d")?

  for hook_dir in ["if-pre-up.d", "if-up.d", "if-down.d", "if-pre-down.d", "if-post-down.d"] {
    fs.write(fp"${dest}/etc/network/${hook_dir}/keep", "")?
  }
}
