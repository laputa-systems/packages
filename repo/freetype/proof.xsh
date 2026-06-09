use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "freetype")?
  print "freetype ok"
}

main(@args)?
