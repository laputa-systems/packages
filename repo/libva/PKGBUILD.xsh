##! XSH module `PKGBUILD` package and build operations.
use pm.env as pm_env
use pm.util as pm_util

## Exported declaration `name`.
export let name = "libva"

## Explicit payload or metapackage classification.
export let package_kind = "payload"

## Exported declaration `ver`.
export let ver = "2.22.0"

## Exported declaration `rel`.
export let rel = "8"

## Exported declaration `deps`.
export let deps = ["musl", "libdrm", "wayland-libs-client"]

## Exported declaration `mkdeps_host`.
export let mkdeps_host = ["llvm-toolchain", "linux", "muon", "samurai", "pkgconf", "libdrm", "wayland-dev"]

## Exported declaration `mkdeps_target`.
export let mkdeps_target = ["wayland-dev"]

## Exported declaration `upstream_sources`.
export let upstream_sources = [
  {
    source: p"https://github.com/intel/libva/releases/download/VERSION/libva-VERSION.tar.bz2",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "e3da2250654c8d52b3f59f8cb3f3d8e7fb1a2ee64378dbc400fbc5663de7edb8",
      },
    ],
  },
]

## Exported declaration `filetree`.
export let filetree = [
  {
    path: p"usr/include/va/va.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_backend.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_backend_prot.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_backend_vpp.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_backend_wayland.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_compat.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_dec_av1.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_dec_hevc.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_dec_jpeg.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_dec_vp8.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_dec_vp9.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_dec_vvc.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_drm.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_drmcommon.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_egl.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_enc_av1.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_enc_h264.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_enc_hevc.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_enc_jpeg.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_enc_mpeg2.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_enc_vp8.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_enc_vp9.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_fei.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_fei_h264.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_fei_hevc.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_prot.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_str.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_tpi.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_version.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_vpp.h",
    kind: "file",
  },
  {
    path: p"usr/include/va/va_wayland.h",
    kind: "file",
  },
  {
    path: p"usr/lib/libva-drm.so",
    kind: "symlink",
  },
  {
    path: p"usr/lib/libva-drm.so.2",
    kind: "symlink",
  },
  {
    path: p"usr/lib/libva-drm.so.2.2200.0",
    kind: "binary",
  },
  {
    path: p"usr/lib/libva-wayland.so",
    kind: "symlink",
  },
  {
    path: p"usr/lib/libva-wayland.so.2",
    kind: "symlink",
  },
  {
    path: p"usr/lib/libva-wayland.so.2.2200.0",
    kind: "binary",
  },
  {
    path: p"usr/lib/libva.so",
    kind: "symlink",
  },
  {
    path: p"usr/lib/libva.so.2",
    kind: "symlink",
  },
  {
    path: p"usr/lib/libva.so.2.2200.0",
    kind: "binary",
  },
  {
    path: p"usr/lib/pkgconfig/libva-drm.pc",
    kind: "file",
  },
  {
    path: p"usr/lib/pkgconfig/libva-wayland.pc",
    kind: "file",
  },
  {
    path: p"usr/lib/pkgconfig/libva.pc",
    kind: "file",
  },
]

## Exported declaration `prepare_sources`.
export proc prepare_sources(src: Path) [fs, error] {
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

## Exported declaration `build`.
export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${cpu.count()}"
  let pc = pm_env.pkg_config_context()?
  let build_root = env.get("XSH_PM_BUILD_ROOT") ?? ""
  let native_scanner = pm_util.build_arch()? != pm_util.target_arch()? and build_root != ""

  let native_tools_ld = if native_scanner {
    f"${build_root}/usr/lib:${build_root}/usr/lib/llvm23/lib:${pc.ld_library_path}"
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
