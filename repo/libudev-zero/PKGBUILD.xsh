use pm.make as make
use pm.util as pm_util

export let name: Str = "libudev-zero"

export let ver: Str = "1.0.3"

export let rel: Str = "2"

export let deps: List[Str] = ["musl", "linux"]

export let mkdeps: List[Str] = ["llvm-toolchain", "linux"]

export let sources: List[Path] = [p"https://github.com/illiliti/libudev-zero/archive/VERSION.tar.gz"]

export let checksums: List[Str] = ["0bd89b657d62d019598e6c7ed726ff8fed80e8ba092a83b484d66afb80b77da5"]

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let arch = pm_util.target_arch()?
  let triple = f"${arch}-linux-musl"
  let cflags = ["-std=c99", "-Wall", "-Wextra", "-Wpedantic", "-Wmissing-prototypes", "-Wstrict-prototypes"]
  let defs = ["-D_XOPEN_SOURCE=700", "-D__user="]
  let includes: List[Str] = []
  let srcs = ["udev.c", "udev_list.c", "udev_device.c", "udev_monitor.c", "udev_enumerate.c"]
  var objs: List[Path] = []
  var tasks: List[make.MakeTask] = []
  var task_deps: List[Str] = []

  for src in srcs {
    let out = fp"obj/${src.replace(".c", ".lo")}"
    let task = make.compile_lo_task(cc, triple, cflags, defs, includes, fp"${src}", out)
    tasks = tasks.push(task)
    task_deps = task_deps.push(task.name)
    objs = objs.push(out)
  }

  let so = p"obj/libudev.so.1"
  tasks = tasks.push(make.link_shared_task(cc, triple, objs, "libudev.so.1", [], so, task_deps))
  make.run_tasks(tasks, make.jobs()?)?
  fs.install(so, fp"${dest}/usr/lib/libudev.so.1", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"libudev.so.1", fp"${dest}/usr/lib/libudev.so")?
  fs.install(p"udev.h", fp"${dest}/usr/include/libudev.h", 0o644, parents: true, overwrite: true)?
  fs.mkdir(fp"${dest}/usr/lib/pkgconfig")?

  fs.write(
    fp"${dest}/usr/lib/pkgconfig/libudev.pc",
    """prefix=/usr
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libudev-zero
Description: Daemonless replacement for libudev
Version: 251
Libs: -L\${libdir} -ludev
Cflags: -I\${includedir}
""",
  )?
}
