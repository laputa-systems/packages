use pm.env as pm_env
use pm.util as pm_util

export let name = "libva"

export let ver = "2.22.0"

export let rel = "6"

export let deps = ["musl", "libdrm", "wayland-libs-client"]

export let mkdeps = ["llvm-toolchain", "linux", "muon", "samurai", "pkgconf", "libdrm", "wayland-dev"]

export let target_build_deps = ["wayland-dev"]

export let sources = [p"https://github.com/intel/libva/releases/download/VERSION/libva-VERSION.tar.bz2"]

export let checksums = [
  "e3da2250654c8d52b3f59f8cb3f3d8e7fb1a2ee64378dbc400fbc5663de7edb8",
]

export proc process_sources(src: Path) [fs, error] {
  let trace = fp"${src}/va/va_trace.c"
  fs.write(trace, trace.read_text()?.replace("syscall(__NR_gettid)", "syscall(SYS_gettid)"))?
}

proc prune_install(dest: Path) [fs, error] {
  fs.remove(fp"${dest}/usr/share/doc", missing_ok: true)?
  fs.remove(fp"${dest}/usr/share/man", missing_ok: true)?

  for static_lib in [p"usr/lib/libva.a", p"usr/lib/libva-drm.a", p"usr/lib/libva-wayland.a"] {
    fs.remove(fp"${dest}/${static_lib}", missing_ok: true)?
  }
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${cpu.count()}"
  let pc = pm_env.pkg_config_context()?
  let build_root = env.get("XSH_PM_BUILD_ROOT") ?? ""
  let native_scanner = pm_util.build_arch()? != pm_util.target_arch()? and build_root != ""

  let native_tools_ld = if native_scanner {
    f"${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib:${pc.ld_library_path}"
  } else {
    pc.ld_library_path
  }

  env {
    LD_LIBRARY_PATH = native_tools_ld
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() "-Ddefault_library=shared" "-Dbuildtype=release" "-Ddriverdir=/usr/lib/dri" "-Ddisable_drm=false" "-Dwith_x11=no" "-Dwith_glx=no" "-Dwith_wayland=yes" "-Dwith_win32=no" "-Denable_docs=false" "build" ?

    if native_scanner {
      let ninja = p"build/build.ninja"
      let scanner_text = fp"${build_root}/usr/bin/wayland-scanner".display()
      fs.write(ninja, ninja.read_text()?.replace("../../../../root/usr/bin/wayland-scanner", scanner_text))?
    }

    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?

  prune_install(dest)?
}
