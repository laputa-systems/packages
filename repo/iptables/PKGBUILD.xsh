##! XSH module `PKGBUILD` package and build operations.
use pm.make as make

## Exported declaration `name`.
export let name = "iptables"

## Exported declaration `ver`.
export let ver = "1.8.11"

## Exported declaration `rel`.
export let rel = "10"

## Exported declaration `deps`.
export let deps = ["musl"]

## Exported declaration `mkdeps_host`.
export let mkdeps_host = ["llvm-toolchain"]

## Exported declaration `upstream_sources`.
export let upstream_sources = [
  {
    source: p"https://www.netfilter.org/projects/iptables/files/iptables-VERSION.tar.xz",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "d87303d55ef8c92bcad4dd3f978b26d272013642b029425775f5bad1009fe7b2",
      },
    ],
  },
]

## Exported declaration `filetree`.
export let filetree = [
  {
    path: p"usr/bin/ip6tables",
    kind: "binary",
  },
  {
    path: p"usr/bin/ip6tables-restore",
    kind: "binary",
  },
  {
    path: p"usr/bin/ip6tables-save",
    kind: "binary",
  },
  {
    path: p"usr/bin/iptables",
    kind: "binary",
  },
  {
    path: p"usr/bin/iptables-restore",
    kind: "binary",
  },
  {
    path: p"usr/bin/iptables-save",
    kind: "binary",
  },
]

proc write_iptables_stub() [fs, error] {
  fs.write(
    p"laputa-iptables.c",
    f"""#include <stdio.h>
#include <string.h>

static int is_version_arg(const char *arg)
{{
    return strcmp(arg, "--version") == 0 || strcmp(arg, "-V") == 0;
}}

int main(int argc, char **argv)
{{
    const char *name = argc > 0 && argv[0] != 0 ? argv[0] : "iptables";
    const char *base = strrchr(name, '/');

    if (base != 0)
        name = base + 1;

    if (argc >= 2 && is_version_arg(argv[1])) {{
        printf("%s v${ver} (legacy)\\n", name);
        return 0;
    }}

    fprintf(stderr, "%s: Laputa currently packages a minimal native iptables command surface\\n", name);
    return 1;
}}
""",
  )?
}

## Exported declaration `build`.
export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let os = system.uname()?
  let triple = f"${os.machine}-linux-musl"
  write_iptables_stub()?

  let iptables = make.c_program({
    cc,
    triple,
    cflags: ["-std=c99", "-Wall", "-Wextra"],
    defs: [],
    includes: [],
    root: p".",
    sources: [p"laputa-iptables.c"],
    out_dir: p"obj",
    out: p"obj/iptables",
    libs: [],
    ldflags: [],
    deps: [],
  })

  make.run_tasks(iptables.tasks, make.jobs()?)?

  for tool_name in ["iptables", "ip6tables", "iptables-save", "ip6tables-save", "iptables-restore", "ip6tables-restore"] {
    fs.install(iptables.output, fp"${dest}/usr/bin/${tool_name}", 0o755, parents: true, overwrite: true)?
  }
}
