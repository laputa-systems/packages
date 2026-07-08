use pm.env as pm_env
export let name = "linux-pam"

export let ver = "1.7.2"

export let rel = "4"

export let deps = ["musl"]

export let mkdeps = ["llvm-toolchain", "linux", "muon", "samurai"]

export let sources = [
  p"https://github.com/linux-pam/linux-pam/releases/download/vVERSION/Linux-PAM-VERSION.tar.xz",
]

export let checksums = ["3d86b6383fb5fd9eb9578d2cd47d92801191f4bf3f9bc61419bfefc8aa1e531a"]

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
