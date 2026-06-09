use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "waterfox-bin")?
  print "waterfox-bin ok"
}

main(@args)?
