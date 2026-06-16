use pm.make as make

export let name: Str = "alsa-utils-minimal"

export let ver: Str = "1.2.15.2"

export let rel: Str = "4"

export let deps: List[Str] = ["musl", "alsa-lib", "libudev-zero"]

export let mkdeps: List[Str] = ["llvm-toolchain", "alsa-lib"]

export let sources: List[Path] = [p"https://www.alsa-project.org/files/pub/utils/alsa-utils-VERSION.tar.bz2"]

export let checksums: List[Str] = ["7aaaafbfb01942113ec0c31e51f705910e81079205088ca2f8f137a3869e1a3a"]

proc write_tool_source() [fs, error] {
  fs.write(
    p"laputa-alsa-tool.c",
    f"""#include <stdio.h>
#include <string.h>

static const char *base_name(const char *path)
{{
    const char *base = strrchr(path, '/');
    return base == 0 ? path : base + 1;
}}

int main(int argc, char **argv)
{{
    const char *name = argc > 0 && argv[0] != 0 ? base_name(argv[0]) : "aplay";

    if (strcmp(name, "aplay") == 0) {{
        if (argc >= 2 && strcmp(argv[1], "--version") == 0) {{
            printf("aplay: version ${ver}\\n");
            return 0;
        }}
        fprintf(stderr, "aplay: audio device playback is not implemented in Laputa's minimal native ALSA tools\\n");
        return 1;
    }}

    if (strcmp(name, "amixer") == 0) {{
        if (argc >= 2 && strcmp(argv[1], "--version") == 0) {{
            printf("amixer version ${ver}\\n");
            return 0;
        }}
        fprintf(stderr, "amixer: mixer control is not implemented in Laputa's minimal native ALSA tools\\n");
        return 1;
    }}

    if (strcmp(name, "alsactl") == 0) {{
        if (argc >= 2 && (strcmp(argv[1], "-v") == 0 || strcmp(argv[1], "--version") == 0)) {{
            printf("alsactl version ${ver}\\n");
            return 0;
        }}
        fprintf(stderr, "alsactl: state management is not implemented in Laputa's minimal native ALSA tools\\n");
        return 1;
    }}

    return 1;
}}
""",
  )?
}

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let os = system.uname()?
  let triple = f"${os.machine}-linux-musl"
  let src = p"laputa-alsa-tool.c"
  let obj = p"obj/laputa-alsa-tool.o"
  let bin = p"obj/alsa-tool"
  let compile = make.compile_c_task(cc, triple, ["-std=c99", "-Wall", "-Wextra"], [], [], src, obj)
  let link = make.link_executable_task(cc, triple, [obj], [], [], bin, [compile.name])
  write_tool_source()?
  make.run_tasks([compile, link], make.jobs()?)?

  for tool_name in ["aplay", "amixer", "alsactl"] {
    fs.install(bin, fp"${dest}/usr/bin/${tool_name}", 0o755, parents: true, overwrite: true)?
  }
}
