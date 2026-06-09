use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "utf8proc")?
  print "utf8proc ok"
}

main(@args)?
