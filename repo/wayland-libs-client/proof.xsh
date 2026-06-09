use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "wayland-libs-client")?
  print "wayland-libs-client ok"
}

main(@args)?
