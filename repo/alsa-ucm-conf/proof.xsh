##! XSH module `proof` package and build operations.
use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "alsa-ucm-conf")?
  print "alsa-ucm-conf ok"
}

main(@args)?
