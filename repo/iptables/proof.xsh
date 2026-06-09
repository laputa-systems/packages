use pm.proof

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  proof.package_metadata(rootfs, "iptables")?
  proof.target_elf(rootfs, p"usr/bin/iptables", "iptables")?
  print "iptables ok"
}

main(@args)?
