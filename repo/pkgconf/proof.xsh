use pm.proof

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  proof.package_metadata(rootfs, "pkgconf")?
  proof.target_elf(rootfs, p"usr/bin/pkgconf", "pkgconf")?

  if ! fs.exists(fp"${rootfs}/usr/bin/pkg-config")? {
    return Err(proof.ProofError.Failed("proof-pkgconf", "missing pkg-config symlink"))?
  }

  print "pkgconf ok"
}

main(@args)?
