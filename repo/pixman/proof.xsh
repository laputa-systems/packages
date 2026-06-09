use pm.proof

proc main(root: Path = /rootfs) [fs, process, env, error] {
  proof.package_metadata(root, "pixman")?
  proof.target_elf(root, p"usr/lib/libpixman-1.so.0", "pixman")?
  print "pixman ok"
}

main(@args)?
