use pm.configure as configure
use pm.make as make
use pm.util as pm_util

export let name: Str = "pkgconf"

export let ver: Str = "2.5.1"

export let rel: Str = "7"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = ["llvm-toolchain"]

export let sources: List[Path] = [p"https://distfiles.ariadne.space/pkgconf/pkgconf-VERSION.tar.xz"]

export let checksums: List[Str] = ["cd05c9589b9f86ecf044c10a2269822bc9eb001eced2582cfffd658b0a50c243"]

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let arch = pm_util.target_arch()?
  let triple = f"${arch}-linux-musl"

  # Step 1: generate libpkgconf/config.h.
  # All HAVE_* values are precomputed for Clang + musl on aarch64 and x86_64.
  # Captured from: configure CC="cc" --prefix=/usr --sysconfdir=/etc --disable-dependency-tracking
  var defines: Map[Str] = {}
  defines["HAVE_DECL_PLEDGE"] = "0"
  defines["HAVE_DECL_REALLOCARRAY"] = "1"
  defines["HAVE_DECL_STRLCAT"] = "1"
  defines["HAVE_DECL_STRLCPY"] = "1"
  defines["HAVE_DECL_STRNDUP"] = "1"
  defines["HAVE_DECL_UNVEIL"] = "0"
  defines["HAVE_DLFCN_H"] = "1"
  defines["HAVE_INTTYPES_H"] = "1"
  defines["HAVE_STDINT_H"] = "1"
  defines["HAVE_STDIO_H"] = "1"
  defines["HAVE_STDLIB_H"] = "1"
  defines["HAVE_STRINGS_H"] = "1"
  defines["HAVE_STRING_H"] = "1"
  defines["HAVE_SYS_STAT_H"] = "1"
  defines["HAVE_SYS_TYPES_H"] = "1"
  defines["HAVE_UNISTD_H"] = "1"
  defines["LT_OBJDIR"] = "\".libs/\""
  defines["PACKAGE"] = "\"pkgconf\""
  defines["PACKAGE_BUGREPORT"] = "\"https://github.com/pkgconf/pkgconf/issues/new\""
  defines["PACKAGE_NAME"] = "\"pkgconf\""
  defines["PACKAGE_STRING"] = f"\"pkgconf ${ver}\""
  defines["PACKAGE_TARNAME"] = "\"pkgconf\""
  defines["PACKAGE_URL"] = "\"\""
  defines["PACKAGE_VERSION"] = f"\"${ver}\""
  defines["STDC_HEADERS"] = "1"
  defines["VERSION"] = f"\"${ver}\""
  configure.config_h(p"libpkgconf/config.h.in", p"libpkgconf/config.h", defines)?

  # Compile flags matching configure's detected values.
  let cflags = ["-g", "-O2", "-Wall", "-Wextra", "-Wformat=2", "-std=gnu99"]

  # HAVE_CONFIG_H pulls in libpkgconf/config.h. The PKG_* and SYSTEM_* constants
  # are set by autoconf as -D flags (not in config.h) based on configure options.
  let defs = [
    "-DHAVE_CONFIG_H",
    "-DPKG_DEFAULT_PATH=\"/usr/lib/pkgconfig:/usr/share/pkgconfig\"",
    "-DSYSTEM_INCLUDEDIR=\"/usr/include\"",
    "-DSYSTEM_LIBDIR=\"/usr/lib\"",
    "-DPERSONALITY_PATH=\"/usr/share/pkgconf/personality.d\"",
  ]

  # -I. finds libpkgconf/config.h; -Ilibpkgconf allows #include <config.h> in libpkgconf sources.
  # -Icli needed for cli/bomtool/main.c to find getopt_long.h
  let includes = ["-I.", "-Ilibpkgconf", "-Icli"]
  fs.mkdir(p"obj")?

  # Step 2: compile libpkgconf (15 source files → PIC .lo objects).
  # File list from Makefile's am_libpkgconf_la_OBJECTS.
  let lib_srcs = [
    "libpkgconf/audit.c",
    "libpkgconf/buffer.c",
    "libpkgconf/cache.c",
    "libpkgconf/client.c",
    "libpkgconf/pkg.c",
    "libpkgconf/bsdstubs.c",
    "libpkgconf/fragment.c",
    "libpkgconf/argvsplit.c",
    "libpkgconf/fileio.c",
    "libpkgconf/tuple.c",
    "libpkgconf/dependency.c",
    "libpkgconf/queue.c",
    "libpkgconf/path.c",
    "libpkgconf/personality.c",
    "libpkgconf/parser.c",
  ]

  var lib_objs: List[Path] = []
  var tasks: List[make.MakeTask] = []
  var lib_deps: List[Str] = []

  for src in lib_srcs {
    let out = fp"obj/${src.replace("/", "-").replace(".c", ".lo")}"
    let task = make.compile_lo_task(cc, triple, cflags, defs, includes, fp"${src}", out)
    tasks = tasks.push(task)
    lib_deps = lib_deps.push(task.name)
    lib_objs = lib_objs.push(out)
  }

  # Step 3: link libpkgconf.so.7.0.0 and static archive.
  let sofile = p"obj/libpkgconf.so.7.0.0"
  let so_task = make.link_shared_task(cc, triple, lib_objs, "libpkgconf.so.7", [], sofile, lib_deps)
  tasks = tasks.push(so_task)
  let static_lib = p"obj/libpkgconf.a"
  let static_task = make.link_archive_task(cc, lib_objs, static_lib, lib_deps)
  tasks = tasks.push(static_task)

  # Step 4: compile and link pkgconf binary.
  # Source files from am_pkgconf_OBJECTS. Automake prefixes objects with the
  # binary name (pkgconf-main.o from main.c) but the sources use plain names.
  let pkgconf_srcs = ["cli/main.c", "cli/getopt_long.c", "cli/renderer-msvc.c"]
  var pkgconf_objs: List[Path] = []
  var pkgconf_deps: List[Str] = []

  for src in pkgconf_srcs {
    let out = fp"obj/pkgconf-${fp"${src}".name.replace(".c", ".o")}"
    let task = make.compile_c_task(cc, triple, cflags, defs, includes, fp"${src}", out)
    tasks = tasks.push(task)
    pkgconf_deps = pkgconf_deps.push(task.name)
    pkgconf_objs = pkgconf_objs.push(out)
  }

  let pkgconf_bin = p"obj/pkgconf"

  tasks = tasks.push(
    make.link_executable_task(
      cc,
      triple,
      pkgconf_objs,
      [static_lib],
      [],
      pkgconf_bin,
      pkgconf_deps.push(static_task.name),
    ),
  )

  # Step 5: compile and link bomtool binary.
  # cli/getopt_long.c is shared with pkgconf; compile separately to a different obj.
  let bomtool_srcs = ["cli/bomtool/main.c", "cli/getopt_long.c"]
  var bomtool_objs: List[Path] = []
  var bomtool_deps: List[Str] = []

  for src in bomtool_srcs {
    let out = fp"obj/bomtool-${fp"${src}".name.replace(".c", ".o")}"
    let task = make.compile_c_task(cc, triple, cflags, defs, includes, fp"${src}", out)
    tasks = tasks.push(task)
    bomtool_deps = bomtool_deps.push(task.name)
    bomtool_objs = bomtool_objs.push(out)
  }

  let bomtool_bin = p"obj/bomtool"

  tasks = tasks.push(
    make.link_executable_task(
      cc,
      triple,
      bomtool_objs,
      [static_lib],
      [],
      bomtool_bin,
      bomtool_deps.push(static_task.name),
    ),
  )

  make.run_tasks(tasks, make.jobs()?)?

  # Step 6: install into dest.
  fs.install(sofile, fp"${dest}/usr/lib/libpkgconf.so.7.0.0", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"libpkgconf.so.7.0.0", fp"${dest}/usr/lib/libpkgconf.so.7")?
  fs.symlink(p"libpkgconf.so.7.0.0", fp"${dest}/usr/lib/libpkgconf.so")?
  fs.install(static_lib, fp"${dest}/usr/lib/libpkgconf.a", 0o644, parents: true, overwrite: true)?
  fs.install(pkgconf_bin, fp"${dest}/usr/bin/pkgconf", 0o755, parents: true, overwrite: true)?
  fs.install(bomtool_bin, fp"${dest}/usr/bin/bomtool", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"pkgconf", fp"${dest}/usr/bin/pkg-config")?

  # Headers: libpkgconf/libpkgconf-api.h, bsdstubs.h, iter.h, libpkgconf.h, stdinc.h
  let headers = fs.files(p"libpkgconf")? |> where .ext == "h"

  for hdr in headers {
    fs.install(hdr.path, fp"${dest}/usr/include/pkgconf/libpkgconf/${hdr.name}", 0o644, parents: true, overwrite: true)?
  }

  # libpkgconf.pc (pkg-config metadata).
  # ${prefix} etc. are pkg-config variable references, not XSH interpolation.
  # Use a template with a placeholder for the version.
  let pc_template = f"""prefix=/usr
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libpkgconf
Description: a library for accessing and manipulating development framework configuration
Version: PKG_VER
Libs: -L\${libdir} -lpkgconf
Cflags: -I\${includedir}/pkgconf
"""

  fs.mkdir(fp"${dest}/usr/lib/pkgconfig")?
  fs.write(fp"${dest}/usr/lib/pkgconfig/libpkgconf.pc", pc_template.replace("PKG_VER", ver))?


}
