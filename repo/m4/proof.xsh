error ScriptError = Failed(kind: Str, message: Str)

proc main(rootfs: Path = /rootfs) [fs, process, error] {
  let tmp = fp"${rootfs}/var/tmp/proof-m4"
  fs.remove(tmp, missing_ok: true)?
  fs.mkdir(tmp)?
  defer fs.remove(tmp, missing_ok: true)?
  let m4 = fp"${rootfs}/usr/bin/m4"

  if ! fs.exists(m4)? {
    return Err(ScriptError.Failed("proof-m4", f"missing m4: ${m4.display()}"))?
  }

  fs.write(
    fp"${tmp}/test.m4",
    """define(GREETING, hello from m4)GREETING
""",
  )?

  # Construct the generated operand from text.  Interpolated `fp` literals
  # resolve as the current directory in the published runner and would pass
  # `proof-m4` itself instead of this file.
  let input = Path(f"${tmp}/test.m4")
  let out = run.text $m4 $input ?
  let trimmed = out.trim()

  if trimmed != "hello from m4" {
    return Err(ScriptError.Failed("proof-m4", f"unexpected output: ${trimmed}"))?
  }

  # Positional operands must remain literal file inputs. A directory must not
  # be silently resolved as the proof cwd by the published XSH runner.
  let directory_stderr = fp"${tmp}/directory-input.stderr"
  let directory_input = process.run(
    process.command_argv(m4, [m4.display(), tmp.display()], stderr: directory_stderr),
  )?

  if directory_input.ok {
    return Err(ScriptError.Failed("proof-m4", "m4 accepted a directory input"))?
  }

  if ! directory_stderr.read_text()?.contains("cannot read non-file input") {
    return Err(ScriptError.Failed("proof-m4", "m4 rejected a directory without its input diagnostic"))?
  }

  print "m4 ok: "${trimmed}
}

main(@args)?
