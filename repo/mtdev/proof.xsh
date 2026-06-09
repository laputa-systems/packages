use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "mtdev")?
  print "mtdev ok"
}

main(@args)?
