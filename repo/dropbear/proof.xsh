use pm.proof as proof
use pm.util as pm_util

error ScriptError = Failed(kind: Str, message: Str)

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  proof.target_elf(rootfs, p"usr/bin/dropbear", "dropbear")?
  proof.target_elf(rootfs, p"usr/bin/dropbearkey", "dropbear")?
  proof.target_elf(rootfs, p"usr/bin/dbclient", "dropbear")?
  let build_arch = pm_util.build_arch()?
  let target_arch = pm_util.target_arch()?

  if build_arch != target_arch {
    print f"dropbear ok: cross-built ${target_arch}"
    return
  }

  let os = system.uname()?
  let arch = os.machine
  let dynlinker = fp"${rootfs}/usr/lib/ld-musl-${arch}.so.1"
  let dropbearkey = fp"${rootfs}/usr/bin/dropbearkey"
  let tmp = /tmp/dropbear-proof
  fs.mkdir(tmp)?

  # RSA: exercises libtommath (big-integer arithmetic) + libtomcrypt (RSA ops).
  let rsa_key = fp"${tmp}/host_rsa"
  run $dynlinker $dropbearkey "-t" "rsa" "-s" "2048" "-f" $rsa_key ?
  let rsa_out = run.text $dynlinker $dropbearkey "-y" "-f" $rsa_key ?

  if ! ("ssh-rsa" in rsa_out) {
    Err(ScriptError.Failed("dropbear-proof", f"rsa: unexpected output: ${rsa_out.trim()}"))?
  }

  print "dropbear ok: rsa 2048 key generated"

  # ed25519: exercises curve25519 (ECC) in libtomcrypt.
  let ed_key = fp"${tmp}/host_ed25519"
  run $dynlinker $dropbearkey "-t" "ed25519" "-f" $ed_key ?
  let ed_out = run.text $dynlinker $dropbearkey "-y" "-f" $ed_key ?

  if ! ("ssh-ed25519" in ed_out) {
    Err(ScriptError.Failed("dropbear-proof", f"ed25519: unexpected output: ${ed_out.trim()}"))?
  }

  print "dropbear ok: ed25519 key generated"

  # ecdsa-256: exercises ECDSA / prime256v1 in libtomcrypt.
  let ec_key = fp"${tmp}/host_ecdsa"
  run $dynlinker $dropbearkey "-t" "ecdsa" "-s" "256" "-f" $ec_key ?
  let ec_out = run.text $dynlinker $dropbearkey "-y" "-f" $ec_key ?

  if ! ("ecdsa-sha2-nistp256" in ec_out) {
    Err(ScriptError.Failed("dropbear-proof", f"ecdsa: unexpected output: ${ec_out.trim()}"))?
  }

  print "dropbear ok: ecdsa-256 key generated"
}

main(@args)?
