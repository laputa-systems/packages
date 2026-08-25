##! XSH module `proof` package and build operations.
use pm.proof

proc main(root: Path = /rootfs) [fs, error] {
  proof.package_metadata(root, "libnl3")?
  proof.ensure(fs.exists(fp"${root}/usr/include/netlink/netlink.h")?, "libnl3", "missing netlink.h")?
  proof.ensure(fs.exists(fp"${root}/usr/include/netlink/genl/genl.h")?, "libnl3", "missing genl.h")?
  proof.ensure(fs.exists(fp"${root}/usr/lib/libnl-3.so")?, "libnl3", "missing libnl-3.so")?
  proof.ensure(fs.exists(fp"${root}/usr/lib/libnl-genl-3.so")?, "libnl3", "missing libnl-genl-3.so")?
  print "libnl3 ok"
}

main(@args)?
