use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "xinit")?
  print "xinit ok"
}

main(@args)?
