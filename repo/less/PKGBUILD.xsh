use pm.make as make
use pm.util as pm_util

export let name = "less"

export let ver = "701"

export let rel = "6"

export let deps = ["musl"]

export let mkdeps = ["llvm-toolchain"]

# Source is a fixed GitHub commit archive (no VERSION substitution needed).
export let sources = [p"https://github.com/laputa-systems/less/archive/0f176037c66cdeb038b39b0b71d9c291363c26ec.tar.gz"]

export let checksums = [
  "846a3b60efa6199bcab518d0934bd83bded678d97e58e8202b55ce7192377f69",
]

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

  let buildgen = make.c_program({
    cc: build_cc,
    triple: build_triple,
    cflags,
    defs: [],
    includes,
    root: p".",
    sources: [p"buildgen.c"],
    out_dir: p"obj/buildgen-objs",
    out: p"obj/buildgen",
    libs: [],
    ldflags: [],
    deps: [],
  })

  var buildgen_tasks = buildgen.tasks

  if cross_build {
    buildgen_tasks = [{...task, env: build_task_env} for task in buildgen_tasks]
  }

  make.run_tasks(buildgen_tasks, make.jobs()?)?
  let less_hlp = p"less.hlp"
  fs.write(p"help.c", run.text $buildgen.output "help" < ${less_hlp}?)?

  let less_srcs = [
    p"main.c",
    p"screen.c",
    p"brac.c",
    p"ch.c",
    p"charset.c",
    p"cmdbuf.c",
    p"command.c",
    p"cvt.c",
    p"decode.c",
    p"edit.c",
    p"evar.c",
    p"filename.c",
    p"forwback.c",
    p"help.c",
    p"ifile.c",
    p"input.c",
    p"jump.c",
    p"line.c",
    p"linenum.c",
    p"lsystem.c",
    p"mark.c",
    p"optfunc.c",
    p"option.c",
    p"opttbl.c",
    p"os.c",
    p"output.c",
    p"pattern.c",
    p"position.c",
    p"prompt.c",
    p"search.c",
    p"signal.c",
    p"tags.c",
    p"ttyin.c",
    p"version.c",
    p"xbuf.c",
  ]

  var funcs_input = ""

  for src in less_srcs {
    funcs_input = f"${funcs_input}${src.read_text()?}"
  }

  fs.write(p"obj/less-srcs.c", funcs_input)?
  let funcs_input_path = p"obj/less-srcs.c"
  fs.write(p"funcs.h", run.text $buildgen.output "funcs" < ${funcs_input_path}?)?

  let less = make.c_program({
    cc,
    triple,
    cflags,
    defs,
    includes,
    root: p".",
    sources: less_srcs.push(p"lesskey_parse.c"),
    out_dir: p"obj/less-objs",
    out: p"obj/less",
    libs: [],
    ldflags: [],
    deps: [],
  })

  make.run_tasks(less.tasks, make.jobs()?)?
  fs.install(less.output, fp"${dest}/usr/bin/less", 0o755, parents: true, overwrite: true)?
  fs.install(p"less-osc8-open.sh", fp"${dest}/usr/libexec/less-osc8-open", 0o755, parents: true, overwrite: true)?
}
