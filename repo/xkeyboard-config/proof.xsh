use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "xkeyboard-config")?
  print "xkeyboard-config ok"
}

main(@args)?
