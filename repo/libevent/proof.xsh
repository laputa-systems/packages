use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "libevent")?
  print "libevent ok"
}

main(@args)?
