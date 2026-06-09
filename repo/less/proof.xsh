use pm.proof

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  proof.package_metadata(rootfs, "less")?
  proof.target_elf(rootfs, p"usr/bin/less", "less")?
  print "less ok"
}

main(@args)?
