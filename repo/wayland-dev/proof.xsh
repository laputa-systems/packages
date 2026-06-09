use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "wayland-dev")?
  print "wayland-dev ok"
}

main(@args)?
