export let name = "baseinit"

export let ver = "2.0.0"

export let rel = "1"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = []

export let checksums: List[Str] = []

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
    """#!/bin/sh
. /usr/lib/init/rc.lib
""",
  )?

  write_file(
    fp"${dest}/usr/lib/init/rc.shutdown",
    """#!/bin/sh
. /usr/lib/init/rc.lib
""",
  )?

  write_file(
    fp"${dest}/usr/lib/init/rc.lib",
    """#!/bin/sh
rc_log() { printf '%s
' "$*"; }
""",
  )?
}
