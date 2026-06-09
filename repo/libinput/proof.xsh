use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "libinput")?
  print "libinput ok"
}

main(@args)?
