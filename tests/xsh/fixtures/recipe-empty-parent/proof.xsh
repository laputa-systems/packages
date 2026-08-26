##! Fixture proof for the empty-parent payload boundary.
use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "recipe-empty-parent")?
}

main(@args)?
