use pm.meson as pm_meson
use pm.util as pm_util

export let name: Str = "libva"

export let ver: Str = "2.22.0"

export let rel: Str = "2"

export let deps: List[Str] = ["musl", "libdrm", "wayland-libs-client"]

export let mkdeps: List[Str] = ["llvm-toolchain", "linux", "muon", "pkgconf", "libdrm", "wayland-dev"]

export let target_build_deps: List[Str] = ["wayland-dev"]

export let sources: List[Path] = [p"https://github.com/intel/libva/releases/download/VERSION/libva-VERSION.tar.bz2"]

export let checksums: List[Str] = ["e3da2250654c8d52b3f59f8cb3f3d8e7fb1a2ee64378dbc400fbc5663de7edb8"]

export proc process_sources(src: Path) [fs, error] {
  let trace = fp"${src}/va/va_trace.c"
  trace.write_atomic(trace.read_text()?.replace("syscall(__NR_gettid)", "syscall(SYS_gettid)"))?
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
  let pc = pm_meson.pkg_config_env()?
  let build_root = env.get("XSH_PM_BUILD_ROOT") ?? ""
  let native_scanner = pm_util.build_arch()? != pm_util.target_arch()? and build_root != ""

  env {
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" "-Dprefix=/usr" "-Dlibdir=lib" "-Ddefault_library=shared" "-Dbuildtype=release" "-Ddriverdir=/usr/lib/dri" "-Ddisable_drm=false" "-Dwith_x11=no" "-Dwith_glx=no" "-Dwith_wayland=yes" "-Dwith_win32=no" "-Denable_docs=false" "build" ?

    if native_scanner {
      let native_scanner_wrapper = fp"${fs.cwd()?}/build/wayland-scanner-native-wrapper"

      fs.write(
        native_scanner_wrapper,
        f"""#!/bin/sh
LD_LIBRARY_PATH="${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib"
export LD_LIBRARY_PATH
exec "${build_root}/usr/bin/wayland-scanner" "$@"
""",
      )?

      fs.chmod(native_scanner_wrapper, 0o755)?
      let ninja = p"build/build.ninja"
      let scanner_text = native_scanner_wrapper.display()
      ninja.write_atomic(ninja.read_text()?.replace("../../../../root/usr/bin/wayland-scanner", scanner_text))?
    }

    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest.display()
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?

  prune_install(dest)?
}
