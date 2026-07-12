use pm.env as pm_env

export let name = "seatd"

export let ver = "0.9.3"

export let rel = "8"

export let deps = ["musl"]

export let mkdeps_host = ["llvm-toolchain", "linux", "muon", "samurai", "pkgconf", "xinit"]

export let upstream_sources = [
  {
    source: p"https://github.com/kennylevinsen/seatd/archive/refs/tags/VERSION.tar.gz",
    kind: "auto",
    architectures: ["all"],
    checksums: [{arch: "all", sha256: "302564d54d8e28191fadfd734f2675ecb0c9e0615a58011b89ef15dfa4dbaa96"}],
  },
  {source: p"service.xsh", kind: "auto", architectures: ["all"], checksums: [{arch: "all", sha256: "SKIP"}]},
]

export let filetree = [
  {path: p"usr/bin/seatd", kind: "binary"},
  {path: p"usr/include/libseat.h", kind: "file"},
  {path: p"usr/lib/libseat.so", kind: "symlink"},
  {path: p"usr/lib/libseat.so.1", kind: "binary"},
  {path: p"usr/lib/pkgconfig/libseat.pc", kind: "file"},
  {path: p"usr/lib/xinit/services/seatd.xsh", kind: "file"},
]

proc patch_linux_headers() [fs, error] {
  fs.mkdir(p"linux")?

  fs.write(
    p"linux/compiler.h",
    """#pragma once
#define __bitwise
#define __force
#define __user
""",
  )?

  fs.write(
    p"linux/input.h",
    """#pragma once
#include <sys/ioctl.h>
#define EVIOCREVOKE _IOW('E', 0x91, int)
""",
  )?

  fs.write(
    p"linux/hidraw.h",
    """#pragma once
#include <sys/ioctl.h>
#define HIDIOCREVOKE _IOW('H', 0x0D, int)
""",
  )?

  fs.write(
    p"linux/kd.h",
    """#pragma once
#define KD_TEXT 0x00
#define KD_GRAPHICS 0x01
#define K_OFF 0x04
#define K_UNICODE 0x03
#define KDSETMODE 0x4B3A
#define KDSKBMODE 0x4B45
""",
  )?

  fs.write(
    p"linux/vt.h",
    """#pragma once
#define VT_AUTO 0x00
#define VT_PROCESS 0x01
#define VT_ACKACQ 0x02
#define VT_SETMODE 0x5602
#define VT_GETSTATE 0x5603
#define VT_RELDISP 0x5605
#define VT_ACTIVATE 0x5606
#define VT_WAITACTIVE 0x5607
struct vt_mode {
  char mode;
  char waitv;
  short relsig;
  short acqsig;
  short frsig;
};
struct vt_stat {
  unsigned short v_active;
  unsigned short v_signal;
  unsigned short v_state;
};
""",
  )?

  fs.write(
    p"linux/major.h",
    """#pragma once
""",
  )?
}

proc patch_realtime_dependency() [fs, error] {
  let meson = p"meson.build"
  let text = fs.read_text(meson)?

  fs.write(
    meson,
    text.replace(
      """# needed for cross-compilation
realtime = meson.get_compiler('c').find_library('rt')
private_deps += realtime""",
      """# musl provides realtime interfaces in libc; avoid recording the build-env librt.
realtime = declare_dependency()""",
    ),
  )?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${cpu.count()}"
  let pc = pm_env.pkg_config_context()?
  patch_linux_headers()?
  patch_realtime_dependency()?

  env {
    CFLAGS = "-I. -D__user="
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() "-Ddefault_library=shared" "-Dwerror=false" "-Dlibseat-logind=disabled" "-Dlibseat-seatd=enabled" "-Dlibseat-builtin=disabled" "-Dserver=enabled" "-Dexamples=disabled" "-Dman-pages=disabled" "build" ?
    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?

  fs.remove(fp"${dest}/usr/bin/seatd-launch", missing_ok: true)?
  fs.install(p"service.xsh", fp"${dest}/usr/lib/xinit/services/seatd.xsh", 0o644, parents: true, overwrite: true)?
}
