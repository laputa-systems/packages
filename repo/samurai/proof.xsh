use pm.proof

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  proof.package_metadata(rootfs, "samurai")?
  proof.target_elf(rootfs, p"usr/bin/samu", "samurai")?

  if ! fs.exists(fp"${rootfs}/usr/bin/ninja")? {
    return Err(proof.ProofError.Failed("proof-samurai", "missing ninja symlink"))?
  }

  print "samurai ok"
}

main(@args)?
