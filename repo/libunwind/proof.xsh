use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "libunwind")?
  print "libunwind ok"
}

main(@args)?
