use pm.make as make
use pm.util as pm_util

export let name: Str = "less"

export let ver: Str = "701"

export let rel: Str = "3"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = ["llvm-toolchain"]

# Source is a fixed GitHub commit archive (no VERSION substitution needed).
export let sources: List[Path] = [
  p"https://github.com/laputa-systems/less/archive/0f176037c66cdeb038b39b0b71d9c291363c26ec.tar.gz",
]

export let checksums: List[Str] = ["846a3b60efa6199bcab518d0934bd83bded678d97e58e8202b55ce7192377f69"]

pure task_names(paths: List[Path]) -> List[Str] {
  return [path_value.display() for path_value in paths]
}

pure less_obj(source: Str) -> Path {
  return fp"obj/${source.replace(".c", ".o")}"
}

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let target_arch = pm_util.target_arch()?
  let build_arch = pm_util.build_arch()?
  let triple = f"${target_arch}-linux-musl"
  let build_triple = f"${build_arch}-linux-musl"
  var build_cc = cc
  let cross_build = build_arch != target_arch
  var build_task_env: Record = {}

  if cross_build {
    let build_root = fp"${env.get("XSH_PM_BUILD_ROOT") ?? ""}"
    build_cc = fp"${build_root}/usr/bin/cc"

    build_task_env = {
      XSH_MAKE_NATIVE_CROSS: "0",
      PATH: f"${build_root}/usr/bin:${build_root}/usr/lib/llvm-toolchain/bin:${env.get("PATH") ?? ""}",
      LD_LIBRARY_PATH: f"${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib",
    }
  }

  let cflags = ["-O2"]
  let defs = ["-DBINDIR=\"/usr/bin\"", "-DLIBEXECDIR=\"/usr/libexec\"", "-DSYSDIR=\"/etc\"", "-DSECURE_COMPILE=0"]
  let includes = ["-I."]
  fs.mkdir(p"obj")?
  let buildgen_obj = p"obj/buildgen.o"
  let buildgen = p"obj/buildgen"

  var buildgen_tasks = [
    make.compile_c_task(build_cc, build_triple, cflags, [], includes, p"buildgen.c", buildgen_obj),
    make.link_executable_task(build_cc, build_triple, [buildgen_obj], [], [], buildgen, [buildgen_obj.display()]),
  ]

  if cross_build {
    buildgen_tasks = [{...task, env: build_task_env} for task in buildgen_tasks]
  }

  make.run_tasks(buildgen_tasks, make.jobs()?)?
  let less_hlp = p"less.hlp"
  fs.write(p"help.c", run.text $buildgen "help" < ${less_hlp}?)?

  let less_srcs = [
    "main.c",
    "screen.c",
    "brac.c",
    "ch.c",
    "charset.c",
    "cmdbuf.c",
    "command.c",
    "cvt.c",
    "decode.c",
    "edit.c",
    "evar.c",
    "filename.c",
    "forwback.c",
    "help.c",
    "ifile.c",
    "input.c",
    "jump.c",
    "line.c",
    "linenum.c",
    "lsystem.c",
    "mark.c",
    "optfunc.c",
    "option.c",
    "opttbl.c",
    "os.c",
    "output.c",
    "pattern.c",
    "position.c",
    "prompt.c",
    "search.c",
    "signal.c",
    "tags.c",
    "ttyin.c",
    "version.c",
    "xbuf.c",
  ]

  var funcs_input = ""

  for src in less_srcs {
    funcs_input = f"${funcs_input}${fp"${src}".read_text()?}"
  }

  fs.write(p"obj/less-srcs.c", funcs_input)?
  let funcs_input_path = p"obj/less-srcs.c"
  fs.write(p"funcs.h", run.text $buildgen "funcs" < ${funcs_input_path}?)?
  var objs: List[Path] = []
  var tasks: List[make.MakeTask] = []

  for src in less_srcs.push("lesskey_parse.c") {
    let out = less_obj(src)
    tasks = tasks.push(make.compile_c_task(cc, triple, cflags, defs, includes, fp"${src}", out))
    objs = objs.push(out)
  }

  let bin = p"obj/less"
  tasks = tasks.push(make.link_executable_task(cc, triple, objs, [], [], bin, task_names(objs)))
  make.run_tasks(tasks, make.jobs()?)?
  let less_nro = p"less.nro.VER".read_text()?.replace("@@VERSION@@", ver).replace("@@DATE@@", "14 May 2026")
  fs.write(p"less.nro", less_nro)?
  fs.install(bin, fp"${dest}/usr/bin/less", 0o755, parents: true, overwrite: true)?
  fs.install(p"less-osc8-open.sh", fp"${dest}/usr/libexec/less-osc8-open", 0o755, parents: true, overwrite: true)?
  fs.install(p"less.nro", fp"${dest}/usr/share/man/man1/less.1", 0o644, parents: true, overwrite: true)?
}
