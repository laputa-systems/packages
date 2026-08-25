##! XSH module `proof` package and build operations.
use pm.proof as proof
use pm.util as pm_util

error ScriptError = Failed(kind: Str, message: Str)

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  let flex = fp"${rootfs}/usr/bin/flex"
  let lex = fp"${rootfs}/usr/bin/lex"

  if ! fs.exists(flex)? {
    return Err(ScriptError.Failed("proof-flex", f"missing flex: ${flex.display()}"))?
  }

  if ! fs.exists(lex)? {
    return Err(ScriptError.Failed("proof-flex", f"missing lex symlink: ${lex.display()}"))?
  }

  proof.target_elf(rootfs, p"usr/bin/flex", "flex")?

  if pm_util.build_arch()? == pm_util.target_arch()? {
    let out = run.text $flex "--version" ?

    if "flex " not in out {
      return Err(ScriptError.Failed("proof-flex", f"flex --version: ${out.trim()}"))?
    }

    let line = out.trim().split("\n")[0]
    print "flex ok: "${line}
  } else {
    print "flex ok: cross-built "${pm_util.target_arch()?}
  }
}

main(@args)?
