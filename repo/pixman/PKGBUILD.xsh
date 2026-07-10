use pm.env as pm_env
use pm.util as pm_util

export let name = "pixman"

export let ver = "0.46.4"

export let rel = "4"

export let deps = ["musl"]

export let mkdeps = ["llvm-toolchain", "muon", "pkgconf", "samurai"]

export let sources = [p"https://xorg.freedesktop.org/releases/individual/lib/pixman-VERSION.tar.xz"]

export let checksums = [
  "a098c33924754ad43f981b740f6d576c70f9ed1006e12221b1845431ebce1239",
]

export proc build(dest: Path) [fs, process, env, error] {
  let jobs_flag = f"-j${cpu.count()}"
  let arch = pm_util.target_arch()?

  if arch == "x86_64" {
    run "muon" "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() "-Ddefault_library=shared" "-Dlibpng=disabled" "-Dgtk=disabled" "-Dtests=disabled" "-Ddemos=disabled" "build" ?
  } else {
    run "muon" "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() "-Ddefault_library=shared" "-Dlibpng=disabled" "-Dgtk=disabled" "-Dtests=disabled" "-Ddemos=disabled" "-Dmmx=disabled" "-Dsse2=disabled" "-Dssse3=disabled" "build" ?
  }

  run "muon" "-C" "build" samu $jobs_flag ?

  env {
    DESTDIR = dest
  } {
    run "muon" "-C" "build" install ?
  } ?

  fs.remove(fp"${dest}/usr/include", missing_ok: true)?
  fs.remove(fp"${dest}/usr/lib/pkgconfig", missing_ok: true)?
  fs.remove(fp"${dest}/usr/lib/libpixman-1.so", missing_ok: true)?
}
