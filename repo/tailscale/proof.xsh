error ProofError = Failed(kind: Str, message: Str)

proc ensure_executable(path_value: Path, label: Str) [fs, error] {
  if ! fs.executable(path_value)? {
    return Err(ProofError.Failed("proof-tailscale", f"missing executable ${label}: ${path_value.display()}"))
  }
}

proc ensure_file(path_value: Path, label: Str) [fs, error] {
  if ! fs.exists(path_value)? {
    return Err(ProofError.Failed("proof-tailscale", f"missing ${label}: ${path_value.display()}"))
  }
}

proc main(rootfs: Path = /rootfs) [fs, error] {
  ensure_executable(fp"${rootfs}/usr/bin/tailscale", "tailscale")?
  ensure_executable(fp"${rootfs}/usr/bin/tailscaled", "tailscaled")?
  ensure_executable(fp"${rootfs}/usr/bin/iptables", "iptables")?
  ensure_file(fp"${rootfs}/usr/lib/xinit/services/tailscaled.xsh", "tailscaled service")?
  print "tailscale ok"
}

main(@args)?
