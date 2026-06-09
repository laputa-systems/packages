use pm.make as make

export let name: Str = "samurai"

export let ver: Str = "1.2"

export let rel: Str = "3"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = ["llvm-toolchain"]

export let sources: List[Path] = [
  p"https://github.com/michaelforney/samurai/releases/download/VERSION/samurai-VERSION.tar.gz",
]

export let checksums: List[Str] = ["3b8cf51548dfc49b7efe035e191ff5e1963ebc4fe8f6064a5eefc5343eaf78a5"]

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let os = system.uname()?
  let triple = f"${os.machine}-linux-musl"

  # samurai has a simple hand-written Makefile; compile all .c files directly.
  # Source list from the Makefile's OBJ variable.
  let cflags = ["-std=c99", "-Wall", "-Wextra", "-Wpedantic", "-Wno-unused-parameter"]
  var objs: List[Path] = []
  var tasks: List[make.MakeTask] = []
  var obj_deps: List[Str] = []

  for s in [
    "build",
    "deps",
    "env",
    "graph",
    "htab",
    "log",
    "parse",
    "samu",
    "scan",
    "tool",
    "tree",
    "util",
  ] {
    let out = fp"obj/${s}.o"
    let task = make.compile_c_task(cc, triple, cflags, [], [], fp"${s}.c", out)
    tasks = tasks.push(task)
    obj_deps = obj_deps.push(task.name)
    objs = objs.push(out)
  }

  let bin = p"obj/samu"
  tasks = tasks.push(make.link_executable_task(cc, triple, objs, [], [], bin, obj_deps))
  make.run_tasks(tasks, make.jobs()?)?

  # Install binary, man page, and ninja symlink.
  fs.install(bin, fp"${dest}/usr/bin/samu", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"samu", fp"${dest}/usr/bin/ninja")?
  fs.install(p"samu.1", fp"${dest}/usr/share/man/man1/samu.1", 0o644, parents: true, overwrite: true)?
}
