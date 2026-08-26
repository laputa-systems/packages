use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "xsh")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/sh")?, "proof-xsh", "missing sh runner")?
  # `xsh` owns the canonical `usr/bin` runners.  A proof root deliberately
  # contains only the node's declared runtime closure, so it must not rely on
  # baselayout's optional `/bin -> usr/bin` compatibility symlink.
  proof.ensure(fs.exists(fp"${root}/usr/bin/xsh")?, "proof-xsh", "missing xsh runner")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/xshi")?, "proof-xsh", "missing xshi runner")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/xsht")?, "proof-xsh", "missing xsht runner")?
  proof.ensure(fs.exists(fp"${root}/usr/lib/xsh/core/cat")?, "proof-xsh", "missing xsh core cat")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/cat")?, "proof-xsh", "missing xsh cat applet")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/ifup")?, "proof-xsh", "missing xsh ifup applet")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/env")?, "proof-xsh", "missing xsh env applet")?
  print "xsh ok"
}

main(@args)?
