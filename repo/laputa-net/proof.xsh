use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "laputa-net")?
  proof.ensure(fs.exists(fp"${root}/usr/lib/xinit/services/net.xsh")?, "laputa-net", "missing net service module")?
  proof.ensure(fs.exists(fp"${root}/etc/network/interfaces")?, "laputa-net", "missing /etc/network/interfaces")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/ifup")?, "laputa-net", "missing /usr/bin/ifup")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/ifdown")?, "laputa-net", "missing /usr/bin/ifdown")?
  proof.ensure(fs.exists(fp"${root}/etc/network/if-pre-down.d")?, "laputa-net", "missing if-pre-down.d")?
  proof.ensure(fs.exists(fp"${root}/etc/network/if-post-down.d")?, "laputa-net", "missing if-post-down.d")?
  print "laputa-net ok"
}

main(@args)?
