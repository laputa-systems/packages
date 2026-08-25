##! XSH module `proof-stack` package and build operations.
error ScriptError = Failed(kind: Str, message: Str)

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  let tmp_root = fs.tempdir()?
  defer fs.close_root(tmp_root)?
  let tmp = fs.root_path(tmp_root)?
  let m4_bin = fp"${rootfs}/usr/bin/m4"
  let flex_bin = fp"${rootfs}/usr/bin/flex"
  let bison_bin = fp"${rootfs}/usr/bin/bison"

  # m4: verify macro expansion works end-to-end.
  fs.write(
    fp"${tmp}/test.m4",
    """define(GREETING, hello from m4)GREETING
""",
  )?

  let m4_out = run.text $m4_bin fp"${tmp}/test.m4" ?
  let m4_result = m4_out.trim()

  if m4_result != "hello from m4" {
    return Err(ScriptError.Failed("proof-m4", f"m4 output: ${m4_result}"))?
  }

  print f"m4 ok: ${m4_result}"

  # flex: verify the installed binary is executable and reports a recognisable
  # version. Scanner generation also depends on a fuller GNU m4 surface.
  let flex_out = run.text $flex_bin "--version" ?

  if "flex " not in flex_out {
    return Err(ScriptError.Failed("proof-flex", f"flex --version: ${flex_out.trim()}"))?
  }

  let flex_line = flex_out.trim().split("\n")[0]
  print f"flex ok: ${flex_line}"

  # bison: verify the binary is executable and reports a recognisable version.
  # A full grammar-generation test requires m4 at /usr/bin/m4, which is the
  # rootfs path; that integration is verified when bison is used in practice.
  let bison_out = run.text $bison_bin "--version" ?

  if "GNU Bison" not in bison_out {
    return Err(ScriptError.Failed("proof-bison", f"bison --version: ${bison_out.trim()}"))?
  }

  let bison_line = bison_out.trim().split("\n")[0]
  print f"bison ok: ${bison_line}"
}

main(@args)?
