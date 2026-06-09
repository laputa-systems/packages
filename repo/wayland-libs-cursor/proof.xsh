use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "wayland-libs-cursor")?
  print "wayland-libs-cursor ok"
}

main(@args)?
