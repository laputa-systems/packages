use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "wlroots0.19-mesa")?
  print "wlroots0.19-mesa ok"
}

main(@args)?
