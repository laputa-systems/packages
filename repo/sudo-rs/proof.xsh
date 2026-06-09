use pm.proof as proof
use pm.util as pm_util

error SudoRsProofError = Failed(kind: Str, message: Str)

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  proof.target_elf(rootfs, p"usr/bin/sudo", "sudo-rs")?
  proof.target_elf(rootfs, p"usr/bin/visudo", "sudo-rs")?
  proof.target_elf(rootfs, p"usr/lib/security/pam_unix.so", "sudo-rs")?
  let readelf = proof.readelf_tool()?
  let pam_unix_so = fp"${rootfs}/usr/lib/security/pam_unix.so"
  let pam_unix = run.text $readelf "-d" $pam_unix_so ?

  if "/build-env/" in pam_unix {
    return Err(SudoRsProofError.Failed("proof-sudo-rs", "pam_unix.so depends on build-env path"))
  }

  let sudo_meta = fp"${rootfs}/usr/bin/sudo".metadata()?

  if ! sudo_meta.setuid {
    return Err(SudoRsProofError.Failed("proof-sudo-rs", "sudo is not setuid"))
  }

  let chkpwd_meta = fp"${rootfs}/usr/bin/unix_chkpwd".metadata()?

  if ! chkpwd_meta.setuid {
    return Err(SudoRsProofError.Failed("proof-sudo-rs", "unix_chkpwd is not setuid"))
  }

  let pam_sudo = fp"${rootfs}/etc/pam.d/sudo".read_text()?

  if ! ("/usr/lib/security/pam_permit.so" in pam_sudo) {
    return Err(
      SudoRsProofError.Failed("proof-sudo-rs", "sudo PAM service does not permit passwordless account/session"),
    )
  }

  let build_arch = pm_util.build_arch()?
  let target_arch = pm_util.target_arch()?

  if build_arch != target_arch {
    print f"sudo-rs ok: cross-built ${target_arch}"
    return
  }

  var sudo = ""

  env {
    LD_LIBRARY_PATH = fp"${rootfs}/usr/lib".display()
  } {
    sudo = run.text fp"${rootfs}/usr/bin/sudo" "--version" ?
  } ?

  if ! ("sudo-rs" in sudo or "Sudo version" in sudo or "sudo " in sudo) {
    return Err(SudoRsProofError.Failed("proof-sudo-rs", f"unexpected sudo version: ${sudo.trim()}"))
  }

  print "sudo-rs ok"
}

main(@args)?
