error ProofError = Failed(kind: Str, message: Str)

proc require_file(root: Path, rel: Str) [fs, error] {
  let path_value = fp"${root}/${rel}"

  if ! fs.exists(path_value)? {
    return Err(ProofError.Failed("proof-baseinit", f"missing ${rel}"))
  }
}

proc main(root: Path = /rootfs) [fs, error] {
  require_file(root, "etc/inittab")?
  require_file(root, "etc/rc.conf")?
  require_file(root, "usr/lib/init/rc.boot")?
  require_file(root, "usr/lib/init/rc.shutdown")?
  require_file(root, "usr/lib/init/rc.lib")?
  print "baseinit ok"
}

main(@args)?
