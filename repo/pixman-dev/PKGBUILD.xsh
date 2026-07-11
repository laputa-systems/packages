use pm.env as pm_env
use pm.util as pm_util

export let name = "pixman-dev"

export let ver = "0.46.4"

export let rel = "7"

export let deps = ["pixman"]

export let mkdeps = ["llvm-toolchain", "muon", "samurai", "pkgconf"]

export let sources = [p"https://xorg.freedesktop.org/releases/individual/lib/pixman-VERSION.tar.xz"]

export let checksums = [
  "a098c33924754ad43f981b740f6d576c70f9ed1006e12221b1845431ebce1239",
]

proc patch_musl_math() [fs, error] {
  let meson = p"meson.build"

  fs.write(
    meson,
    meson.read_text()?.replace(
      "dep_m = cc.find_library('m', required : false)",
      "dep_m = declare_dependency(link_args : ['-lm'])",
    ),
  )?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${cpu.count()}"
  let pc = pm_env.pkg_config_context()?
  let arch = pm_util.target_arch()?
  patch_musl_math()?

  env {
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    if arch == "x86_64" {
      run $muon "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() "-Ddefault_library=shared" "-Dlibpng=disabled" "-Dgtk=disabled" "-Dtests=disabled" "-Ddemos=disabled" "build" ?
    } else {
      run $muon "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() "-Ddefault_library=shared" "-Dlibpng=disabled" "-Dgtk=disabled" "-Dtests=disabled" "-Ddemos=disabled" "-Dmmx=disabled" "-Dsse2=disabled" "-Dssse3=disabled" "build" ?
    }

    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?

  for entry in fs.ls(fp"${dest}/usr/lib")? {
    if entry.name.starts_with("libpixman-1.so.") {
      fs.remove(entry.path, missing_ok: true)?
    }
  }
}

export let filetree = [
  {path: p"usr/include/pixman-1/pixman-version.h", kind: "file"},
  {path: p"usr/include/pixman-1/pixman.h", kind: "file"},
  {path: p"usr/lib/libpixman-1.so", kind: "symlink"},
  {path: p"usr/lib/pkgconfig/pixman-1.pc", kind: "file"},
]
