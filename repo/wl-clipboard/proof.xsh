use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "wl-clipboard")?
  print "wl-clipboard ok"
}

main(@args)?
