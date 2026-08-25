##! XSH module `proof` package and build operations.
use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "libevdev")?
  print "libevdev ok"
}

main(@args)?
