##! Package recipe metadata and build operations.
use pm.make as make

## Package recipe export.
export let name = "samurai"

## Explicit payload or metapackage classification.
export let package_kind = "payload"

## Package recipe export.
export let ver = "1.2"

## Package recipe export.
export let rel = "9"

## Package recipe export.
export let deps = ["musl"]

## Package recipe export.
export let mkdeps_host = ["llvm-toolchain"]

## Package recipe export.
export let upstream_sources = [
  {
    source: p"https://github.com/michaelforney/samurai/releases/download/VERSION/samurai-VERSION.tar.gz",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "3b8cf51548dfc49b7efe035e191ff5e1963ebc4fe8f6064a5eefc5343eaf78a5",
      },
    ],
  },
]

## Package recipe export.
export let filetree = [{path: p"usr/bin/ninja", kind: "symlink"}, {path: p"usr/bin/samu", kind: "binary"}]

## Package recipe export.
export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let os = system.uname()?
  let triple = f"${os.machine}-linux-musl"

  # samurai has a simple hand-written Makefile; compile all .c files directly.
  # Source list from the Makefile's OBJ variable.
  let cflags = ["-std=c99", "-Wall", "-Wextra", "-Wpedantic", "-Wno-unused-parameter"]

  let samu = make.c_program(
    {
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
    },
  )

  make.run_tasks(samu.tasks, make.jobs()?)?

  # Install binary and ninja symlink.
  fs.install(samu.output, fp"${dest}/usr/bin/samu", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"samu", fp"${dest}/usr/bin/ninja")?
}
