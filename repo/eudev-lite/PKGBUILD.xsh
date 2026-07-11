use pm.make as make

export let name = "eudev-lite"

export let ver = "3.2.14"

export let rel = "7"

export let deps = ["musl"]

export let mkdeps = ["llvm-toolchain"]

export let sources = [p"https://github.com/eudev-project/eudev/releases/download/vVERSION/eudev-VERSION.tar.gz"]

export let checksums = [
  "8da4319102f24abbf7fff5ce9c416af848df163b29590e666d334cc1927f006f",
]

proc write_udev_stub() [fs, error] {
  fs.write(
    p"laputa-udev.c",
    f"""#include <stdio.h>
#include <string.h>

static int wants_version(int argc, char **argv)
{{
    return argc >= 2 && (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "-V") == 0);
}}

int main(int argc, char **argv)
{{
    const char *name = argc > 0 && argv[0] != 0 ? argv[0] : "udevadm";
    const char *base = strrchr(name, '/');

    if (base != 0)
        name = base + 1;

    if (wants_version(argc, argv)) {{
        printf("${ver}\\n");
        return 0;
    }}

    if (strcmp(name, "udevd") == 0 || strcmp(name, "systemd-udevd") == 0)
        return 0;

    if (argc >= 2 && (strcmp(argv[1], "trigger") == 0 || strcmp(argv[1], "settle") == 0 || strcmp(argv[1], "control") == 0))
        return 0;

    fprintf(stderr, "%s: Laputa currently packages a minimal native udev command surface\\n", name);
    return 1;
}}
""",
  )?
}

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let os = system.uname()?
  let triple = f"${os.machine}-linux-musl"
  write_udev_stub()?

  let udev = make.c_program({
    cc,
    triple,
    cflags: ["-std=c99", "-Wall", "-Wextra"],
    defs: [],
    includes: [],
    root: p".",
    sources: [p"laputa-udev.c"],
    out_dir: p"obj",
    out: p"obj/udev",
    libs: [],
    ldflags: [],
    deps: [],
  })

  make.run_tasks(udev.tasks, make.jobs()?)?
  fs.install(udev.output, fp"${dest}/usr/bin/udevadm", 0o755, parents: true, overwrite: true)?
  fs.install(udev.output, fp"${dest}/usr/bin/udevd", 0o755, parents: true, overwrite: true)?
  fs.install(udev.output, fp"${dest}/usr/lib/udev/systemd-udevd", 0o755, parents: true, overwrite: true)?
  fs.mkdir(fp"${dest}/run")?
  fs.mkdir(fp"${dest}/run/udev")?
  fs.mkdir(fp"${dest}/usr/lib/udev")?
  fs.mkdir(fp"${dest}/usr/lib/udev/rules.d")?
}

export let filetree = [
  {path: p"usr/bin/udevadm", kind: "binary"},
  {path: p"usr/bin/udevd", kind: "binary"},
  {path: p"usr/lib/udev/systemd-udevd", kind: "binary"},
]
