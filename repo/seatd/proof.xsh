use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "seatd")?
  print "seatd ok"
}

main(@args)?
