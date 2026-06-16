use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "laputa-net")?
  proof.ensure(fs.exists(fp"${root}/usr/lib/xinit/services/net.xsh")?, "laputa-net", "missing net service module")?
  proof.ensure(fs.exists(fp"${root}/etc/network/interfaces")?, "laputa-net", "missing /etc/network/interfaces")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/ifup")?, "laputa-net", "missing /usr/bin/ifup")?
  print "laputa-net ok"
}

main(@args)?
