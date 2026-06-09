use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "xsh")?
  proof.ensure(fs.exists(fp"${root}/usr/local/bin/xsh-multicall")?, "proof-xsh", "missing xsh multicall")?
  proof.ensure(fs.exists(fp"${root}/usr/lib/xsh/core/cat.xsh")?, "proof-xsh", "missing xsh core cat")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/cat")?, "proof-xsh", "missing xsh core cat link")?
  print "xsh ok"
}

main(@args)?
