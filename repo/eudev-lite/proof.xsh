use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "eudev-lite")?
  print "eudev-lite ok"
}

main(@args)?
