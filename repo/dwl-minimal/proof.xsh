use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "dwl-minimal")?
  print "dwl-minimal ok"
}

main(@args)?
