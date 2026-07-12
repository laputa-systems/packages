use pm.make as make
use pm.util as pm_util

export let name = "libudev-zero"

export let ver = "1.0.3"

export let rel = "7"

export let deps = ["musl", "linux"]

export let mkdeps_host = ["llvm-toolchain", "linux"]

export let upstream_sources = [
  {source: p"https://github.com/illiliti/libudev-zero/archive/VERSION.tar.gz", kind: "auto", architectures: ["all"], checksums: [{arch: "all", sha256: "0bd89b657d62d019598e6c7ed726ff8fed80e8ba092a83b484d66afb80b77da5"}]}
]



export let filetree = [
  {path: p"usr/include/libudev.h", kind: "file"},
  {path: p"usr/lib/libudev.so", kind: "symlink"},
  {path: p"usr/lib/libudev.so.1", kind: "binary"},
  {path: p"usr/lib/pkgconfig/libudev.pc", kind: "file"},
]

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let arch = pm_util.target_arch()?
  let triple = f"${arch}-linux-musl"
  let cflags = ["-std=c99", "-Wall", "-Wextra", "-Wpedantic", "-Wmissing-prototypes", "-Wstrict-prototypes"]
  let defs = ["-D_XOPEN_SOURCE=700", "-D__user="]
  let includes = []
  let srcs = [p"udev.c", p"udev_list.c", p"udev_device.c", p"udev_monitor.c", p"udev_enumerate.c"]

  let libudev = make.c_shared_library({
    cc,
    triple,
    cflags,
    defs,
    includes,
    root: p".",
    sources: srcs,
    out_dir: p"obj",
    out: p"obj/libudev.so.1",
    soname: "libudev.so.1",
    ldflags: [],
    deps: [],
  })

  make.run_tasks(libudev.tasks, make.jobs()?)?
  fs.install(libudev.output, fp"${dest}/usr/lib/libudev.so.1", 0o755, parents: true, overwrite: true)?
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
