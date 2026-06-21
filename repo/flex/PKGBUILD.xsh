use pm.configure as configure
use pm.make as make
use pm.util as pm_util

export let name: Str = "flex"

export let ver: Str = "2.6.4"

export let rel: Str = "6"

export let deps: List[Str] = ["musl", "m4"]

export let mkdeps: List[Str] = ["llvm-toolchain"]

export let sources: List[Path] = [
  p"https://github.com/westes/flex/releases/download/vVERSION/flex-VERSION.tar.gz",
  p"files/flex.xsh",
]

export let checksums: List[Str] = [
  "e87aae032bf07c26f85ac0ed3250998c37621d95f8bd748b31f15b33c45ee995",
  "1619dfa4377e04000e4143d04bc008dd5652fd36501065a35ce9892029eeeed7",
]

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let arch = pm_util.target_arch()?
  let triple = f"${arch}-linux-musl"

  # Generate src/config.h from src/config.h.in.
  # Values captured from: CC="cc" ./configure --prefix=/usr --disable-nls
  # on x86_64 and aarch64 with Clang targeting musl.  flex has no
  # arch-specific configure probes so one set of values covers both.
  var defines: Map[Str] = {}
  defines["HAVE_ALLOCA"] = "1"
  defines["HAVE_ALLOCA_H"] = "1"
  defines["HAVE_DLFCN_H"] = "1"
  defines["HAVE_DUP2"] = "1"
  defines["HAVE_FORK"] = "1"
  defines["HAVE_INTTYPES_H"] = "1"
  defines["HAVE_LIBM"] = "1"
  defines["HAVE_LIMITS_H"] = "1"
  defines["HAVE_LOCALE_H"] = "1"
  defines["HAVE_MALLOC"] = "1"
  defines["HAVE_MEMORY_H"] = "1"
  defines["HAVE_MEMSET"] = "1"
  defines["HAVE_NETINET_IN_H"] = "1"
  defines["HAVE_POW"] = "1"
  defines["HAVE_PTHREAD_H"] = "1"
  defines["HAVE_REALLOC"] = "1"
  defines["HAVE_REALLOCARRAY"] = "1"
  defines["HAVE_REGCOMP"] = "1"
  defines["HAVE_REGEX_H"] = "1"
  defines["HAVE_SETLOCALE"] = "1"
  defines["HAVE_STDBOOL_H"] = "1"
  defines["HAVE_STDINT_H"] = "1"
  defines["HAVE_STDLIB_H"] = "1"
  defines["HAVE_STRCASECMP"] = "1"
  defines["HAVE_STRCHR"] = "1"
  defines["HAVE_STRDUP"] = "1"
  defines["HAVE_STRINGS_H"] = "1"
  defines["HAVE_STRING_H"] = "1"
  defines["HAVE_STRTOL"] = "1"
  defines["HAVE_SYS_STAT_H"] = "1"
  defines["HAVE_SYS_TYPES_H"] = "1"
  defines["HAVE_SYS_WAIT_H"] = "1"
  defines["HAVE_UNISTD_H"] = "1"
  defines["HAVE_VFORK"] = "1"
  defines["HAVE_WORKING_FORK"] = "1"
  defines["HAVE_WORKING_VFORK"] = "1"
  defines["HAVE__BOOL"] = "1"
  defines["LT_OBJDIR"] = "\".libs/\""

  # M4: path bison uses at runtime to invoke m4 skeleton expansion.
  defines["M4"] = "\"/usr/bin/m4\""
  defines["PACKAGE"] = "\"flex\""
  defines["PACKAGE_BUGREPORT"] = "\"flex-help@lists.sourceforge.net\""
  defines["PACKAGE_NAME"] = "\"the fast lexical analyser generator\""
  defines["PACKAGE_STRING"] = f"\"the fast lexical analyser generator ${ver}\""
  defines["PACKAGE_TARNAME"] = "\"flex\""
  defines["PACKAGE_URL"] = "\"\""
  defines["PACKAGE_VERSION"] = f"\"${ver}\""
  defines["STDC_HEADERS"] = "1"
  defines["VERSION"] = f"\"${ver}\""

  # YYTEXT_POINTER: flex generates char *yytext (not char yytext[]).
  defines["YYTEXT_POINTER"] = "1"
  configure.config_h(p"src/config.h.in", p"src/config.h", defines)?
  let cflags = ["-g", "-O2"]
  let defs = ["-DHAVE_CONFIG_H"]

  # -Isrc: finds both config.h (generated above) and flexdef.h.
  let includes = ["-Isrc"]
  fs.mkdir(p"obj")?
  var objs: List[Path] = []
  var tasks: List[make.MakeTask] = []
  var obj_deps: List[Str] = []

  # Compile the flex binary sources from src/.
  # libmain.c and libyywrap.c are part of libfl (scanner support library),
  # not the flex binary itself — exclude them.
  for e in fs.ls(p"src")? |> where .ext == "c" and .name != "libmain.c" and .name != "libyywrap.c" {
    let out = fp"obj/${e.name.replace(".c", ".o")}"
    let task = make.compile_c_task(cc, triple, cflags, defs, includes, e.path, out)
    tasks = tasks.push(task)
    obj_deps = obj_deps.push(task.name)
    objs = objs.push(out)
  }

  # lib/ contains only two gnulib wrappers (malloc.c, realloc.c).
  # With HAVE_MALLOC=1 and HAVE_REALLOC=1 musl's implementations are used
  # directly, so no rpl_* symbols are needed; omit lib/ from the link.
  let bin = p"obj/flex"
  tasks = tasks.push(make.link_executable_task(cc, triple, objs, [], [], bin, obj_deps))
  make.run_tasks(tasks, make.jobs()?)?
  fs.install(bin, fp"${dest}/usr/bin/flex", 0o755, parents: true, overwrite: true)?

  # POSIX requires a 'lex' command; flex is the canonical implementation.
  fs.symlink(p"flex", fp"${dest}/usr/bin/lex")?
  fs.install(p"flex.xsh", fp"${dest}/usr/lib/pm/repo/flex/files/flex.xsh", 0o755, parents: true, overwrite: true)?
}
