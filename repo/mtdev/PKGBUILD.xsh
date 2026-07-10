use pm.make as make
use pm.util as pm_util

export let name = "mtdev"

export let ver = "1.1.7"

export let rel = "3"

export let deps = ["musl", "linux"]

export let mkdeps = ["llvm-toolchain", "linux"]

export let sources = [p"http://bitmath.org/code/mtdev/mtdev-VERSION.tar.gz"]

export let checksums = [
  "a55bd02a9af4dd266c0042ec608744fff3a017577614c057da09f1f4566ea32c",
]

proc write_config() [fs, error] {
  fs.write(
    p"config.h",
    f"""#ifndef MTDEV_CONFIG_H
#define MTDEV_CONFIG_H

#define PACKAGE "mtdev"
#define PACKAGE_NAME "Multitouch Protocol Translation Library"
#define PACKAGE_TARNAME "mtdev"
#define PACKAGE_VERSION "${ver}"
#define PACKAGE_STRING "Multitouch Protocol Translation Library ${ver}"
#define PACKAGE_BUGREPORT "mtdev@lists.freedesktop.org"
#define PACKAGE_URL ""
#define VERSION "${ver}"
#define STDC_HEADERS 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1

#endif
""",
  )?
}

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let arch = pm_util.target_arch()?
  let triple = f"${arch}-linux-musl"
  let cflags = ["-O2", "-Wall"]
  let defs = ["-DHAVE_CONFIG_H", "-D__user="]
  let includes = ["-Iinclude", "-Isrc", "-I."]
  write_config()?

  let libmtdev = make.c_shared_library({
    cc,
    triple,
    cflags,
    defs,
    includes,
    root: p".",
    sources: [p"src/caps.c", p"src/core.c", p"src/iobuf.c", p"src/match.c", p"src/match_four.c"],
    out_dir: p"obj",
    out: p"obj/libmtdev.so.1.0.0",
    soname: "libmtdev.so.1",
    ldflags: [],
    deps: [],
  })

  make.run_tasks(libmtdev.tasks, make.jobs()?)?
  fs.install(libmtdev.output, fp"${dest}/usr/lib/libmtdev.so.1.0.0", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"libmtdev.so.1.0.0", fp"${dest}/usr/lib/libmtdev.so.1")?
  fs.symlink(p"libmtdev.so.1.0.0", fp"${dest}/usr/lib/libmtdev.so")?
  make.install_header_tree(p"include", fp"${dest}/usr/include")?
  fs.mkdir(fp"${dest}/usr/lib/pkgconfig")?

  fs.write(
    fp"${dest}/usr/lib/pkgconfig/mtdev.pc",
    f"""prefix=/usr
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: mtdev
Description: Multitouch Protocol Translation Library
Version: ${ver}
Libs: -L\${libdir} -lmtdev
Cflags: -I\${includedir}
""",
  )?
}
