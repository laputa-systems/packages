use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "tllist")?
  print "tllist ok"
}

main(@args)?
