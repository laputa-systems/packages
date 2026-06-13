error ScriptError = Failed(kind: Str, message: Str)

proc main(rootfs: Path = /rootfs) [fs, process, error] {
  let tmp_root = fs.tempdir()?
  defer fs.close_root(tmp_root)?
  let tmp = fs.root_path(tmp_root)?
  let m4 = fp"${rootfs}/usr/bin/m4"

  if ! fs.exists(m4)? {
    return Err(ScriptError.Failed("proof-m4", f"missing m4: ${m4.display()}"))?
  }

  fs.write(
    fp"${tmp}/test.m4",
    """define(GREETING, hello from m4)GREETING
""",
  )?

  let out = run.text (m4.display()) (fp"${tmp}/test.m4".display()) ?
  let trimmed = out.trim()

  if trimmed != "hello from m4" {
    return Err(ScriptError.Failed("proof-m4", f"unexpected output: ${trimmed}"))?
  }

  print "m4 ok: "${trimmed}
}

main(@args)?
