use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "xsh")?
  proof.ensure(fs.exists(fp"${root}/usr/local/bin/xsh")?, "proof-xsh", "missing xsh runner")?
  proof.ensure(fs.exists(fp"${root}/usr/local/bin/xshi")?, "proof-xsh", "missing xshi runner")?
  proof.ensure(fs.exists(fp"${root}/usr/local/bin/xsht")?, "proof-xsh", "missing xsht runner")?
  proof.ensure(fs.exists(fp"${root}/usr/lib/xsh/core/cat.xsh")?, "proof-xsh", "missing xsh core cat")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/cat")?, "proof-xsh", "missing xsh core cat link")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/sh")?, "proof-xsh", "missing sh wrapper")?
  print "xsh ok"
}

main(@args)?
