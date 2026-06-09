use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "alsa-lib")?
  print "alsa-lib ok"
}

main(@args)?
