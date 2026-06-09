use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "mesa-minimal")?
  print "mesa-minimal ok"
}

main(@args)?
