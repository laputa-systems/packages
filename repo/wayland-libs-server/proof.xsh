use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "wayland-libs-server")?
  print "wayland-libs-server ok"
}

main(@args)?
