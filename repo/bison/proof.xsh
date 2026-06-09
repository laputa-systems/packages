use pm.proof

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  proof.package_metadata(rootfs, "bison")?
  proof.target_elf(rootfs, p"usr/bin/bison", "bison")?
  print "bison ok"
}

main(@args)?
