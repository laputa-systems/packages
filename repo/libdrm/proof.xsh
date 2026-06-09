use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "libdrm")?
  print "libdrm ok"
}

main(@args)?
