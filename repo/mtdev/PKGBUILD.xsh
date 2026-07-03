use pm.make as make
use pm.util as pm_util

export let name: Str = "mtdev"

export let ver: Str = "1.1.7"

export let rel: Str = "3"

export let deps: List[Str] = ["musl", "linux"]

export let mkdeps: List[Str] = ["llvm-toolchain", "linux"]

export let sources: List[Path] = [p"http://bitmath.org/code/mtdev/mtdev-VERSION.tar.gz"]

export let checksums: List[Str] = ["a55bd02a9af4dd266c0042ec608744fff3a017577614c057da09f1f4566ea32c"]

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
  let srcs = ["src/caps.c", "src/core.c", "src/iobuf.c", "src/match.c", "src/match_four.c"]
  var objs: List[Path] = []
  var tasks: List[make.MakeTask] = []
  var task_deps: List[Str] = []
  write_config()?

  for src in srcs {
    let out = fp"obj/${src.replace("/", "-").replace(".c", ".lo")}"
    let task = make.compile_lo_task(cc, triple, cflags, defs, includes, fp"${src}", out)
    tasks = tasks.push(task)
    task_deps = task_deps.push(task.name)
    objs = objs.push(out)
  }

  let so = p"obj/libmtdev.so.1.0.0"
  tasks = tasks.push(make.link_shared_task(cc, triple, objs, "libmtdev.so.1", [], so, task_deps))
  make.run_tasks(tasks, make.jobs()?)?
  fs.install(so, fp"${dest}/usr/lib/libmtdev.so.1.0.0", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"libmtdev.so.1.0.0", fp"${dest}/usr/lib/libmtdev.so.1")?
  fs.symlink(p"libmtdev.so.1.0.0", fp"${dest}/usr/lib/libmtdev.so")?

  for header in ["mtdev-mapping.h", "mtdev-plumbing.h", "mtdev.h"] {
    fs.install(fp"include/${header}", fp"${dest}/usr/include/${header}", 0o644, parents: true, overwrite: true)?
  }

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
