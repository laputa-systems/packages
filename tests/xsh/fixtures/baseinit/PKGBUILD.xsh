export let name = "baseinit"

export let ver = "2.0.0"

export let rel = "1"

export let deps = []

export let mkdeps_host = []

export let upstream_sources = []

export let filetree = [
  {path: p"etc/inittab", kind: "file"},
  {path: p"etc/rc.conf", kind: "file"},
  {path: p"usr/lib/init/rc.boot", kind: "file"},
  {path: p"usr/lib/init/rc.lib", kind: "file"},
  {path: p"usr/lib/init/rc.shutdown", kind: "file"},
]

proc write_file(path_value: Path, text: Str) [fs, error] {
  fs.mkdir(path_value.parent)?
  fs.write(path_value, text)?
}

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  write_file(
    fp"${dest}/etc/inittab",
    """::sysinit:/usr/lib/init/rc.boot
::shutdown:/usr/lib/init/rc.shutdown
""",
  )?

  write_file(
    fp"${dest}/etc/rc.conf",
    """HOSTNAME=laputa
""",
  )?

  write_file(
    fp"${dest}/usr/lib/init/rc.boot",
    """#!/bin/xsh
print "boot"
""",
  )?

  write_file(
    fp"${dest}/usr/lib/init/rc.shutdown",
    """#!/bin/xsh
print "shutdown"
""",
  )?

  write_file(
    fp"${dest}/usr/lib/init/rc.lib",
    """#!/bin/xsh
export proc rc_log(...parts: List[Str]) {
  print parts.join(" ")
}
""",
  )?
}
