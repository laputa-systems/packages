export let name: Str = "laputa-net"

export let ver: Str = "1"

export let rel: Str = "1"

# ifup (the DHCP/static client) is an xsh core applet; the net service drives it.
export let deps: List[Str] = ["xsh"]

export let mkdeps: List[Str] = []

export let sources: List[Path] = [p"service.xsh", p"interfaces"]

export let checksums: List[Str] = ["SKIP", "SKIP"]

export proc build(dest: Path) [fs, error] {
  fs.install(p"service.xsh", fp"${dest}/usr/lib/xinit/services/net.xsh", 0o644, parents: true, overwrite: true)?
  fs.install(p"interfaces", fp"${dest}/etc/network/interfaces", 0o644, parents: true, overwrite: true)?
  fs.mkdir(fp"${dest}/etc/network/if-pre-up.d")?
  fs.mkdir(fp"${dest}/etc/network/if-up.d")?
  fs.mkdir(fp"${dest}/etc/network/if-down.d")?

  # Expose the ifup core applet as a command for the net service and operators.
  fs.symlink(../lib/xsh/core/ifup.xsh, fp"${dest}/usr/bin/ifup")?
}
