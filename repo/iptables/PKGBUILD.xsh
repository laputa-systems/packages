use pm.make as make

export let name: Str = "iptables"

export let ver: Str = "1.8.11"

export let rel: Str = "4"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = ["llvm-toolchain"]

export let sources: List[Path] = [p"https://www.netfilter.org/projects/iptables/files/iptables-VERSION.tar.xz"]

export let checksums: List[Str] = ["d87303d55ef8c92bcad4dd3f978b26d272013642b029425775f5bad1009fe7b2"]

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

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let os = system.uname()?
  let triple = f"${os.machine}-linux-musl"
  let src = p"laputa-iptables.c"
  let obj = p"obj/laputa-iptables.o"
  let bin = p"obj/iptables"
  let compile = make.compile_c_task(cc, triple, ["-std=c99", "-Wall", "-Wextra"], [], [], src, obj)
  let link = make.link_executable_task(cc, triple, [obj], [], [], bin, [compile.name])
  write_iptables_stub()?
  make.run_tasks([compile, link], make.jobs()?)?

  for tool_name in ["iptables", "ip6tables", "iptables-save", "ip6tables-save", "iptables-restore", "ip6tables-restore"] {
    fs.install(bin, fp"${dest}/usr/bin/${tool_name}", 0o755, parents: true, overwrite: true)?
  }
}
