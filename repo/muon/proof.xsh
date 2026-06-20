use pm.proof as proof
use pm.util as pm_util

error ScriptError = Failed(kind: Str, message: Str)

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  let muon = fp"${rootfs}/usr/bin/muon"

  if ! fs.exists(muon)? {
    return Err(ScriptError.Failed("proof-muon", f"missing muon: ${muon.display()}"))?
  }

  proof.target_elf(rootfs, p"usr/bin/muon", "muon")?

  if pm_util.build_arch()? == pm_util.target_arch()? {
    let out = run.text muon.display() "version" ?
    let trimmed = out.trim()

    if trimmed == "" {
      return Err(ScriptError.Failed("proof-muon", "muon version produced no output"))?
    }

    print "muon ok: "${trimmed}
  } else {
    print "muon ok: cross-built "${pm_util.target_arch()?}
  }
}

main(@args)?
