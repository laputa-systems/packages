use pm.make as make

export let name = "samurai"

export let ver = "1.2"

export let rel = "8"

export let deps = ["musl"]

export let mkdeps_host = ["llvm-toolchain"]

export let sources = [p"https://github.com/michaelforney/samurai/releases/download/VERSION/samurai-VERSION.tar.gz"]

export let checksums = ["3b8cf51548dfc49b7efe035e191ff5e1963ebc4fe8f6064a5eefc5343eaf78a5"]

export let filetree = [{path: p"usr/bin/ninja", kind: "symlink"}, {path: p"usr/bin/samu", kind: "binary"}]

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let os = system.uname()?
  let triple = f"${os.machine}-linux-musl"

  # samurai has a simple hand-written Makefile; compile all .c files directly.
  # Source list from the Makefile's OBJ variable.
  let cflags = ["-std=c99", "-Wall", "-Wextra", "-Wpedantic", "-Wno-unused-parameter"]

  let samu = make.c_program({
    cc,
    triple,
    cflags,
    defs: [],
    includes: [],
    root: p".",
    sources: [
      p"build.c",
      p"deps.c",
      p"env.c",
      p"graph.c",
      p"htab.c",
      p"log.c",
      p"parse.c",
      p"samu.c",
      p"scan.c",
      p"tool.c",
      p"tree.c",
      p"util.c",
    ],
    out_dir: p"obj",
    out: p"obj/samu",
    libs: [],
    ldflags: [],
    deps: [],
  })

  make.run_tasks(samu.tasks, make.jobs()?)?

  # Install binary and ninja symlink.
  fs.install(samu.output, fp"${dest}/usr/bin/samu", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"samu", fp"${dest}/usr/bin/ninja")?
}
