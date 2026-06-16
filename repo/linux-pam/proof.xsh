use pm.util as pm_util

error LinuxPamProofError = Failed(kind: Str, message: Str)

proc ensure(condition: Bool, kind: Str, message: Str) [error] {
  if ! condition {
    Err(LinuxPamProofError.Failed(kind, message))?
  }
}

proc main(rootfs: Path = /rootfs) [fs, env, error] {
  let arch = pm_util.target_arch()?
  ensure(fs.exists(fp"${rootfs}/usr/lib/libpam.so.0")?, "proof-linux-pam", "missing libpam")
  ensure(fs.exists(fp"${rootfs}/usr/lib/security/pam_unix.so")?, "proof-linux-pam", "missing pam_unix")
  ensure(fs.exists(fp"${rootfs}/usr/lib/security/pam_rootok.so")?, "proof-linux-pam", "missing pam_rootok")
  ensure(fs.exists(fp"${rootfs}/usr/lib/security/pam_permit.so")?, "proof-linux-pam", "missing pam_permit")
  ensure(fs.exists(fp"${rootfs}/etc/pam.d/sudo")?, "proof-linux-pam", "missing sudo PAM service")
  ensure(fs.exists(fp"${rootfs}/etc/pam.d/su")?, "proof-linux-pam", "missing su PAM service")
  ensure(fs.exists(fp"${rootfs}/etc/pam.d/su-l")?, "proof-linux-pam", "missing su-l PAM service")
  print f"linux-pam ok: ${arch}"
}

main(@args)?
