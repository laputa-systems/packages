use pm.meson as pm_meson
use pm.util as pm_util

export let name: Str = "pixman"

export let ver: Str = "0.46.4"

export let rel: Str = "4"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = ["llvm-toolchain", "muon", "pkgconf"]

export let sources: List[Path] = [p"https://xorg.freedesktop.org/releases/individual/lib/pixman-VERSION.tar.xz"]

export let checksums: List[Str] = ["a098c33924754ad43f981b740f6d576c70f9ed1006e12221b1845431ebce1239"]

proc patch_musl_math() [fs, error] {
  let meson = p"meson.build"

  meson.write_atomic(
    meson.read_text()?.replace(
      "dep_m = cc.find_library('m', required : false)",
      "dep_m = declare_dependency(link_args : ['-lm'])",
    ),
  )?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${cpu.count()}"
  let pc = pm_meson.pkg_config_env()?
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
      run $muon "setup" "-Dprefix=/usr" "-Dlibdir=lib" "-Ddefault_library=shared" "-Dlibpng=disabled" "-Dgtk=disabled" "-Dtests=disabled" "-Ddemos=disabled" "build" ?
    } else {
      run $muon "setup" "-Dprefix=/usr" "-Dlibdir=lib" "-Ddefault_library=shared" "-Dlibpng=disabled" "-Dgtk=disabled" "-Dtests=disabled" "-Ddemos=disabled" "-Dmmx=disabled" "-Dsse2=disabled" "-Dssse3=disabled" "build" ?
    }
    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest.display()
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?

  fs.remove(fp"${dest}/usr/include", missing_ok: true)?
  fs.remove(fp"${dest}/usr/lib/pkgconfig", missing_ok: true)?
  fs.remove(fp"${dest}/usr/lib/libpixman-1.so", missing_ok: true)?
}
