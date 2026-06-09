use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "alsa-utils-minimal")?
  print "alsa-utils-minimal ok"
}

main(@args)?
