use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "libffi")?
  print "libffi ok"
}

main(@args)?
