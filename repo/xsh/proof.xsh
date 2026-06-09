use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "xsh")?
  print "xsh ok"
}

main(@args)?
