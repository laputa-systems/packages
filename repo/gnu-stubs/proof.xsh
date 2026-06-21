use pm.util as pm_util

error ProofError = Failed(kind: Str, message: Str)

proc main(rootfs: Path = /rootfs) [fs, error] {
  for path_value in [
    fp"${rootfs}/usr/lib/crtbeginS.o",
    fp"${rootfs}/usr/lib/crtendS.o",
    fp"${rootfs}/usr/lib/libgcc_s.so",
    fp"${rootfs}/usr/lib/libgcc_s.so.1",
  ] {
    if ! fs.exists(path_value)? {
      return Err(ProofError.Failed("proof-gnu-stubs", f"missing ${path_value.strip_prefix(rootfs)?.display()}"))
    }
  }

  let link = fp"${rootfs}/usr/lib/libgcc_s.so.1".readlink()?

  if link.display() != "libgcc_s.so" {
    return Err(ProofError.Failed("proof-gnu-stubs", f"libgcc_s.so.1 symlink points to ${link}"))
  }

  print "gnu-stubs ok"
}

main(@args)?
