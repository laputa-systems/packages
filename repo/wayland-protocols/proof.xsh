use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "wayland-protocols")?
  print "wayland-protocols ok"
}

main(@args)?
