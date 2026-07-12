use pm.env as pm_env

export let name = "linux-pam"

export let ver = "1.7.2"

export let rel = "8"

export let deps = ["musl"]

export let mkdeps_host = ["llvm-toolchain", "linux", "muon", "samurai"]

export let upstream_sources = [
  {source: p"https://github.com/linux-pam/linux-pam/releases/download/vVERSION/Linux-PAM-VERSION.tar.xz", kind: "auto", architectures: ["all"], checksums: [{arch: "all", sha256: "3d86b6383fb5fd9eb9578d2cd47d92801191f4bf3f9bc61419bfefc8aa1e531a"}]}
]



export let filetree = [
  {path: p"etc/pam.d/su", kind: "file"},
  {path: p"etc/pam.d/su-l", kind: "file"},
  {path: p"etc/pam.d/sudo", kind: "file"},
  {path: p"etc/security/access.conf", kind: "file"},
  {path: p"etc/security/faillock.conf", kind: "file"},
  {path: p"etc/security/group.conf", kind: "file"},
  {path: p"etc/security/limits.conf", kind: "file"},
  {path: p"etc/security/namespace.conf", kind: "file"},
  {path: p"etc/security/namespace.init", kind: "file"},
  {path: p"etc/security/pam_env.conf", kind: "file"},
  {path: p"etc/security/pwhistory.conf", kind: "file"},
  {path: p"etc/security/time.conf", kind: "file"},
  {path: p"usr/bin/faillock", kind: "binary"},
  {path: p"usr/bin/mkhomedir_helper", kind: "binary"},
  {path: p"usr/bin/pam_namespace_helper", kind: "file"},
  {path: p"usr/bin/pam_timestamp_check", kind: "binary"},
  {path: p"usr/bin/pwhistory_helper", kind: "binary"},
  {path: p"usr/bin/unix_chkpwd", kind: "binary"},
  {path: p"usr/include/security/_pam_compat.h", kind: "file"},
  {path: p"usr/include/security/_pam_macros.h", kind: "file"},
  {path: p"usr/include/security/_pam_types.h", kind: "file"},
  {path: p"usr/include/security/pam_appl.h", kind: "file"},
  {path: p"usr/include/security/pam_client.h", kind: "file"},
  {path: p"usr/include/security/pam_ext.h", kind: "file"},
  {path: p"usr/include/security/pam_filter.h", kind: "file"},
  {path: p"usr/include/security/pam_misc.h", kind: "file"},
  {path: p"usr/include/security/pam_modules.h", kind: "file"},
  {path: p"usr/include/security/pam_modutil.h", kind: "file"},
  {path: p"usr/lib/libpam.so", kind: "symlink"},
  {path: p"usr/lib/libpam.so.0", kind: "symlink"},
  {path: p"usr/lib/libpam.so.0.85.1", kind: "binary"},
  {path: p"usr/lib/libpam_misc.so", kind: "symlink"},
  {path: p"usr/lib/libpam_misc.so.0", kind: "symlink"},
  {path: p"usr/lib/libpam_misc.so.0.82.1", kind: "binary"},
  {path: p"usr/lib/libpamc.so", kind: "symlink"},
  {path: p"usr/lib/libpamc.so.0", kind: "symlink"},
  {path: p"usr/lib/libpamc.so.0.82.1", kind: "binary"},
  {path: p"usr/lib/pkgconfig/pam.pc", kind: "file"},
  {path: p"usr/lib/pkgconfig/pam_misc.pc", kind: "file"},
  {path: p"usr/lib/pkgconfig/pamc.pc", kind: "file"},
  {path: p"usr/lib/security/pam_access.so", kind: "binary"},
  {path: p"usr/lib/security/pam_canonicalize_user.so", kind: "binary"},
  {path: p"usr/lib/security/pam_debug.so", kind: "binary"},
  {path: p"usr/lib/security/pam_deny.so", kind: "binary"},
  {path: p"usr/lib/security/pam_echo.so", kind: "binary"},
  {path: p"usr/lib/security/pam_env.so", kind: "binary"},
  {path: p"usr/lib/security/pam_exec.so", kind: "binary"},
  {path: p"usr/lib/security/pam_faildelay.so", kind: "binary"},
  {path: p"usr/lib/security/pam_faillock.so", kind: "binary"},
  {path: p"usr/lib/security/pam_filter.so", kind: "binary"},
  {path: p"usr/lib/security/pam_filter/upperLOWER", kind: "binary"},
  {path: p"usr/lib/security/pam_ftp.so", kind: "binary"},
  {path: p"usr/lib/security/pam_group.so", kind: "binary"},
  {path: p"usr/lib/security/pam_issue.so", kind: "binary"},
  {path: p"usr/lib/security/pam_limits.so", kind: "binary"},
  {path: p"usr/lib/security/pam_listfile.so", kind: "binary"},
  {path: p"usr/lib/security/pam_localuser.so", kind: "binary"},
  {path: p"usr/lib/security/pam_loginuid.so", kind: "binary"},
  {path: p"usr/lib/security/pam_mail.so", kind: "binary"},
  {path: p"usr/lib/security/pam_mkhomedir.so", kind: "binary"},
  {path: p"usr/lib/security/pam_motd.so", kind: "binary"},
  {path: p"usr/lib/security/pam_namespace.so", kind: "binary"},
  {path: p"usr/lib/security/pam_nologin.so", kind: "binary"},
  {path: p"usr/lib/security/pam_permit.so", kind: "binary"},
  {path: p"usr/lib/security/pam_pwhistory.so", kind: "binary"},
  {path: p"usr/lib/security/pam_rootok.so", kind: "binary"},
  {path: p"usr/lib/security/pam_securetty.so", kind: "binary"},
  {path: p"usr/lib/security/pam_shells.so", kind: "binary"},
  {path: p"usr/lib/security/pam_stress.so", kind: "binary"},
  {path: p"usr/lib/security/pam_succeed_if.so", kind: "binary"},
  {path: p"usr/lib/security/pam_time.so", kind: "binary"},
  {path: p"usr/lib/security/pam_timestamp.so", kind: "binary"},
  {path: p"usr/lib/security/pam_umask.so", kind: "binary"},
  {path: p"usr/lib/security/pam_unix.so", kind: "binary"},
  {path: p"usr/lib/security/pam_usertype.so", kind: "binary"},
  {path: p"usr/lib/security/pam_warn.so", kind: "binary"},
  {path: p"usr/lib/security/pam_wheel.so", kind: "binary"},
  {path: p"usr/lib/security/pam_xauth.so", kind: "binary"},
  {path: p"usr/lib/systemd/system/pam_namespace.service", kind: "file"},
]

proc patch_modules() [fs, error] {
  let root_build = p"meson.build"
  var root_text = root_build.read_text()?

  root_text = root_text.replace(
    """subdir('conf' / 'pam_conv1')
""",
    "",
  )

  root_text = root_text.replace(
    """libcrypt = dependency('libcrypt', 'libxcrypt', required: false)
if not libcrypt.found()
  libcrypt = cc.find_library('crypt')
endif
""",
    """libcrypt = declare_dependency(link_args: ['-lcrypt'])
""",
  )

  fs.write(root_build, root_text)?
  let modules_build = p"modules/meson.build"

  let modules_text = modules_build.read_text()?.replace(
    """subdir('pam_setquota')
""",
    "",
  )

  fs.write(modules_build, modules_text)?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${cpu.count()}"
  patch_modules()?

  let setup_args = [
    "setup",
    pm_env.meson_prefix_arg(),
    pm_env.meson_libdir_arg(),
    pm_env.meson_sysconfdir_arg(),
    "-Dsbindir=/usr/bin",
    "-Di18n=disabled",
    "-Ddocs=disabled",
    "-Daudit=disabled",
    "-Deconf=disabled",
    "-Dlogind=disabled",
    "-Delogind=disabled",
    "-Dopenssl=disabled",
    "-Dpwaccess=disabled",
    "-Dselinux=disabled",
    "-Dnis=disabled",
    "-Dexamples=false",
    "-Dxtests=false",
    "-Dpam_userdb=disabled",
    "-Dpam_lastlog=disabled",
    "-Dpam_unix=enabled",
    "-Dvendordir=",
    "build",
  ]

  run $muon ${setup_args} ?
  run $muon "-C" "build" samu $jobs_flag ?

  env {
    DESTDIR = dest
  } {
    run $muon "-C" "build" install ?
  } ?

  fs.remove(fp"${dest}/etc/environment", missing_ok: true)?
  fs.chmod(fp"${dest}/usr/bin/unix_chkpwd", 0o4755)?
  fs.mkdir(fp"${dest}/etc/pam.d")?

  fs.write(
    fp"${dest}/etc/pam.d/sudo",
    """auth required /usr/lib/security/pam_unix.so
account required /usr/lib/security/pam_permit.so
session required /usr/lib/security/pam_permit.so
""",
  )?

  fs.write(
    fp"${dest}/etc/pam.d/su",
    """auth sufficient /usr/lib/security/pam_rootok.so
auth required /usr/lib/security/pam_unix.so
account required /usr/lib/security/pam_permit.so
session required /usr/lib/security/pam_permit.so
""",
  )?

  fs.write(
    fp"${dest}/etc/pam.d/su-l",
    """auth sufficient /usr/lib/security/pam_rootok.so
auth required /usr/lib/security/pam_unix.so
account required /usr/lib/security/pam_permit.so
session required /usr/lib/security/pam_permit.so
""",
  )?
}
