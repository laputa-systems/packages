use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "mdevd")?
  print "mdevd ok"
}

main(@args)?
