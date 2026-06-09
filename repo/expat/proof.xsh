use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "expat")?
  print "expat ok"
}

main(@args)?
