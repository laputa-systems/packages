use pm.make as make
use pm.util as pm_util

error MuslError = Failed(message: Str)

export let name = "musl"

export let ver = "1.2.6"

export let rel = "15"

export let deps = []

export let mkdeps = ["llvm-toolchain"]

export let nostrip = true

export let sources = [p"https://musl.libc.org/releases/musl-VERSION.tar.gz"]

export let checksums = ["d585fd3b613c66151fc3249e8ed44f77020cb5e6c1e635a616d3f9f82460512a"]

export let checksums_aarch64 = [
  "d585fd3b613c66151fc3249e8ed44f77020cb5e6c1e635a616d3f9f82460512a",
]

export let checksums_x86_64 = [
  "d585fd3b613c66151fc3249e8ed44f77020cb5e6c1e635a616d3f9f82460512a",
]

export let filetree = [
  {path: p"usr", kind: "tree"},
  {path: p"usr/lib/Scrt1.o", kind: "binary"},
  {path: p"usr/lib/crt1.o", kind: "binary"},
  {path: p"usr/lib/crti.o", kind: "binary"},
  {path: p"usr/lib/crtn.o", kind: "binary"},
  {path: p"usr/lib/ld-musl-aarch64.so.1", kind: "symlink"},
  {path: p"usr/lib/libc.so", kind: "binary"},
  {path: p"usr/lib/libcrypt.a", kind: "symlink"},
  {path: p"usr/lib/libcrypt.so", kind: "symlink"},
  {path: p"usr/lib/libdl.a", kind: "symlink"},
  {path: p"usr/lib/libdl.so", kind: "symlink"},
  {path: p"usr/lib/libm.a", kind: "symlink"},
  {path: p"usr/lib/libm.so", kind: "symlink"},
  {path: p"usr/lib/libpthread.a", kind: "symlink"},
  {path: p"usr/lib/libpthread.so", kind: "symlink"},
  {path: p"usr/lib/librt.a", kind: "symlink"},
  {path: p"usr/lib/librt.so", kind: "symlink"},
  {path: p"usr/lib/rcrt1.o", kind: "binary"},
]

pure regex_captures(text: Str, pattern: Str) -> Result[List[Str]] {
  let re = regex.compile(pattern)?
  return re.captures(text)
}

proc compiler_rt_builtins(arch: Str) [fs, error] -> Result[List[Path]] {
  let target_root = p"llvm-toolchain-target"

  let candidates = [
    fp"${target_root}/usr/lib/llvm22/lib/clang/22/lib/${arch}-linux-musl/libclang_rt.builtins-${arch}.a",
    fp"${target_root}/lib/llvm22/lib/clang/22/lib/${arch}-linux-musl/libclang_rt.builtins-${arch}.a",
    fp"/usr/lib/llvm22/lib/clang/22/lib/${arch}-linux-musl/libclang_rt.builtins-${arch}.a",
    fp"/usr/lib/llvm22/lib/clang/22/lib/linux/libclang_rt.builtins-${arch}.a",
    fp"/usr/lib/libclang_rt.builtins-${arch}.a",
  ]

  for candidate in candidates {
    if fs.exists(candidate)? {
      return [candidate]
    }
  }

  []
}

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let arch = pm_util.target_arch()?
  let triple = f"${arch}-linux-musl"

  # Generate include/bits/alltypes.h and include/bits/syscall.h.
  # bits/ does not exist in the source tree — create it first.
  fs.mkdir(p"include/bits")?

  # Replicates tools/mkalltypes.sed.
  # Input: arch/ARCH/bits/alltypes.h.in then include/alltypes.h.in (concatenated).
  # TYPEDEF T name;  →  #if defined(__NEED_name) && !defined(__DEFINED_name)
  #                     typedef T name;
  #                     #define __DEFINED_name
  #                     #endif
  # STRUCT name body; and UNION name body; get equivalent struct/union wrappers.
  # All other lines (#define, #if, #endif, blank, etc.) pass through unchanged.
  let arch_at = fs.read_text(fp"arch/${arch}/bits/alltypes.h.in")?
  let generic_at = fs.read_text(p"include/alltypes.h.in")?
  var at_lines = []

  for line in [arch_at, generic_at].join("\n").split("\n") {
    if line.starts_with("TYPEDEF ") {
      let caps = regex_captures(line, "^TYPEDEF (.+) ([^ ]+);$")?
      let type_expr = caps[1]
      let type_name = caps[2]
      at_lines = at_lines.push(f"#if defined(__NEED_${type_name}) && !defined(__DEFINED_${type_name})")
      at_lines = at_lines.push(f"typedef ${type_expr} ${type_name};")
      at_lines = at_lines.push(f"#define __DEFINED_${type_name}")
      at_lines = at_lines.push("#endif")
    } else if line.starts_with("STRUCT ") {
      let caps = regex_captures(line, "^STRUCT +([^ ]+) (.+);$")?
      let sname = caps[1]
      let sbody = caps[2]
      at_lines = at_lines.push(f"#if defined(__NEED_struct_${sname}) && !defined(__DEFINED_struct_${sname})")
      at_lines = at_lines.push(f"struct ${sname} ${sbody};")
      at_lines = at_lines.push(f"#define __DEFINED_struct_${sname}")
      at_lines = at_lines.push("#endif")
    } else if line.starts_with("UNION ") {
      let caps = regex_captures(line, "^UNION +([^ ]+) (.+);$")?
      let uname = caps[1]
      let ubody = caps[2]
      at_lines = at_lines.push(f"#if defined(__NEED_union_${uname}) && !defined(__DEFINED_union_${uname})")
      at_lines = at_lines.push(f"union ${uname} ${ubody};")
      at_lines = at_lines.push(f"#define __DEFINED_union_${uname}")
      at_lines = at_lines.push("#endif")
    } else {
      at_lines = at_lines.push(line)
    }
  }

  fs.write(p"include/bits/alltypes.h", at_lines.join("\n"))?

  # Generate include/bits/syscall.h: rename __NR_* → SYS_*.
  let syscall_in = fs.read_text(fp"arch/${arch}/bits/syscall.h.in")?
  fs.write(p"include/bits/syscall.h", syscall_in.replace("__NR_", "SYS_"))?

  # Generate src/internal/version.h (included by src/internal/version.c).
  # configure normally produces this from tools/version.sh + VERSION file.
  fs.write(
    p"src/internal/version.h",
    f"""#define VERSION "${ver}"
""",
  )?

  # Compilation flags matching musl configure output for Clang + musl targets.
  # -U_FORTIFY_SOURCE: Clang enables _FORTIFY_SOURCE by default, injecting
  #   LOCAL __memcpy_chk wrappers that shadow musl's assembly GLOBAL memcpy.
  # -fno-sanitize=all: UBSan instrumentation introduces HIDDEN memcpy references
  #   which ELF visibility merging demotes, poisoning musl's exported symbols.
  let cflags = [
    "-std=c99",
    "-nostdinc",
    "-ffreestanding",
    "-fexcess-precision=standard",
    "-frounding-math",
    "-Wa,--noexecstack",
    "-D_XOPEN_SOURCE=700",
    "-O2",
    "-pipe",
    "-U_FORTIFY_SOURCE",
    "-fno-sanitize=all",
  ]

  let includes = [f"-I./arch/${arch}", "-I./arch/generic", "-I./src/include", "-I./src/internal", "-I./include"]

  # Collect arch-override stems and files from two sources, matching musl's
  # Makefile ARCH_SRCS = arch/$(ARCH)/*.{c,s} + src/*/{arch}/*.[csS]:
  # 1. arch/${arch}/*.{c,s} — top-level arch overrides (empty for aarch64/x86_64)
  # 2. src/{subsystem}/${arch}/*.[csS] — in-source arch overrides (math, thread,
  #    signal, etc. optimised assembly/C for the target architecture)
  # A file in either location with stem FOO shadows any src/*/FOO.c generic file.
  var arch_stems = []
  var arch_c_files = []
  var arch_s_files = []

  # 1. arch/${arch}/ direct children (headers only for aarch64/x86_64 in practice).
  for e in fs.ls(fp"arch/${arch}")? |> where .kind == "file" {
    if e.ext == "c" {
      arch_stems = arch_stems.push(e.name.replace(".c", ""))
      arch_c_files = arch_c_files.push(e.path)
    } else if e.ext == "s" or e.ext == "S" {
      arch_stems = arch_stems.push(e.name.replace(f".${e.ext}", ""))
      arch_s_files = arch_s_files.push(e.path)
    }
  }

  # 2. src/{subsystem}/${arch}/*.[csS] — in-source arch overrides.
  for subsys in fs.ls(p"src")? |> where .kind == "dir" {
    let arch_subdir = fp"${subsys.path.display()}/${arch}"

    if fs.exists(arch_subdir)? {
      for e in fs.ls(arch_subdir)? |> where .kind == "file" {
        if e.ext == "c" {
          arch_stems = arch_stems.push(e.name.replace(".c", ""))
          arch_c_files = arch_c_files.push(e.path)
        } else if e.ext == "s" or e.ext == "S" {
          arch_stems = arch_stems.push(e.name.replace(f".${e.ext}", ""))
          arch_s_files = arch_s_files.push(e.path)
        }
      }
    }
  }

  # Enumerate src/ .c files, matching musl's Makefile: SRC_DIRS = src/* (one
  # level deep per subsystem) plus src/malloc/mallocng (two levels, the default
  # malloc implementation). Files with stems matching any arch-override entry are
  # excluded — their arch version is compiled instead.
  # fs.ls is non-recursive here intentionally: src/{subsystem}/{arch}/*.c files
  # at two levels deep must not be included (they are wrong-arch implementations).
  var libc_srcs = []

  for subsys in fs.ls(p"src")? |> where .kind == "dir" {
    for e in fs.ls(subsys.path)? |> where .ext == "c" {
      if ! (e.name.replace(".c", "") in arch_stems) {
        libc_srcs = libc_srcs.push(e.path)
      }
    }
  }

  # src/malloc/mallocng/*.c — the default malloc implementation (two levels deep).
  for e in fs.ls(p"src/malloc/mallocng")? |> where .ext == "c" {
    libc_srcs = libc_srcs.push(e.path)
  }

  fs.mkdir(p"obj")?

  # Compile all src/ sources → LOBJS (PIC; go into both libc.a and libc.so).
  var tasks = []
  let libc = make.compile_lo_tasks(cc, triple, cflags, [], includes, p"", libc_srcs, p"obj/libc")
  tasks = tasks.extend(libc.tasks)

  # Compile arch/ C overrides → LOBJS.
  let arch_c = make.compile_lo_tasks(cc, triple, cflags, [], includes, p"", arch_c_files, p"obj/arch")
  tasks = tasks.extend(arch_c.tasks)
  var lobjs = libc.objects.extend(arch_c.objects)
  var lobj_deps = libc.deps.extend(arch_c.deps)

  # Compile arch/ assembly overrides → LOBJS (skip C-specific flags; include
  # paths still passed for any .S files that use the C preprocessor).
  let arch_asm = make.compile_asm_lo_tasks(cc, triple, includes, p"", arch_s_files, p"obj/arch-asm")
  tasks = tasks.extend(arch_asm.tasks)
  lobj_deps = lobj_deps.extend(arch_asm.deps)
  lobjs = lobjs.extend(arch_asm.objects)

  # Compile top-level ldso/ → LDSO_OBJS (PIC; libc.so only, not in libc.a).
  # ldso/dlstart.c defines _dlstart (ELF entry of libc.so / the dynamic linker).
  # ldso/dynlink.c is the main dynamic-linker implementation.
  # Hardcoded list — ldso/ contains exactly these two files in every musl release.
  var ldso_objs = []
  var ldso_deps = []
  fs.mkdir(p"obj/ldso")?
  let ldso_sources = [fp"ldso/${src_name}.c" for src_name in ["dlstart", "dynlink"]]
  let ldso_compile = make.compile_lo_tasks(cc, triple, cflags, [], includes, p"", ldso_sources, p"obj/ldso")
  tasks = tasks.extend(ldso_compile.tasks)
  ldso_objs = ldso_compile.objects
  ldso_deps = ldso_compile.deps

  # libc.a — static archive from LOBJS only (ldso not needed for static linking).
  let libc_a = p"obj/libc.a"
  tasks = tasks.push(make.link_archive_task(cc, lobjs, libc_a, lobj_deps))

  # libc.so — LOBJS + LDSO_OBJS. musl's floating-point paths can use compiler-rt
  # helpers, so link the builtins archive after musl's own objects when it is
  # available and let the linker pull only unresolved helper objects.
  let libc_so = p"obj/libc.so"
  var all_so_objs = lobjs
  var all_so_deps = lobj_deps

  for obj in ldso_objs {
    all_so_objs = all_so_objs.push(obj)
  }

  all_so_deps = all_so_deps.extend(ldso_deps)
  let builtins = compiler_rt_builtins(arch)?
  all_so_objs = all_so_objs.extend(builtins)

  let so_ldflags = [
    "-shared",
    "-nostdlib",
    "-fno-sanitize=all",
    "-Wl,--sort-section,alignment",
    "-Wl,--sort-common",
    "-Wl,--hash-style=both",
    "-Wl,-e,_dlstart",
  ]

  var so_argv = [cc, "-target", triple]
  so_argv = so_argv.extend(so_ldflags)

  for obj in all_so_objs {
    so_argv = so_argv.push(obj)
  }

  so_argv = so_argv.extend(["-o", libc_so])

  tasks = tasks.push({
    name: libc_so.display(),
    outputs: [libc_so],
    inputs: all_so_objs,
    deps: all_so_deps,
    argv: so_argv,
    cwd: p".",
    env: {},
    depfile: p"",
    stamp: fp"${libc_so}.cmd",
  })

  make.run_tasks(tasks, make.jobs()?)?

  # CRT startup objects — compiled with -DCRT, installed as .o files.
  # Non-PIE: crt1, crti, crtn (compile_c, no -fPIC).
  # PIE:     Scrt1, rcrt1 (compile_lo adds -fPIC/-DPIC for PIE executables).
  let crt_cflags = cflags.push("-DCRT")
  var crt_tasks = []
  var crt_outs: List[Path] = []

  for src_name in ["crt1", "crti", "crtn"] {
    let src = fp"crt/${src_name}.c"
    let out = fp"obj/${src_name}.o"
    let task = make.compile_c_task(cc, triple, crt_cflags, [], includes, src, out)
    crt_tasks = crt_tasks.push({...task, stamp: p""})
    crt_outs = crt_outs.push(out)
  }

  for src_name in ["Scrt1", "rcrt1"] {
    let src = fp"crt/${src_name}.c"
    let out = fp"obj/${src_name}.o"
    let task = make.compile_lo_task(cc, triple, crt_cflags, [], includes, src, out)
    crt_tasks = crt_tasks.push({...task, stamp: p""})
    crt_outs = crt_outs.push(out)
  }

  make.run_tasks(crt_tasks, make.jobs()?)?

  for out in crt_outs {
    fs.install(out, fp"${dest}/usr/lib/${out.name()}", 0o644, parents: true, overwrite: true)?
  }

  # Install shared library and static archive.
  fs.install(libc_so, fp"${dest}/usr/lib/libc.so", 0o755, parents: true, overwrite: true)?
  fs.install(libc_a, fp"${dest}/usr/lib/libc.a", 0o644, parents: true, overwrite: true)?

  for builtin in builtins {
    fs.install(builtin, fp"${dest}/usr/lib/${builtin.name()}", 0o644, parents: true, overwrite: true)?
  }

  let packaged_builtin = fp"llvm-toolchain-target/usr/lib/llvm22/lib/clang/22/lib/linux/libclang_rt.builtins-${arch}.a"

  if fs.exists(packaged_builtin)? {
    fs.install(packaged_builtin, fp"${dest}/usr/lib/${packaged_builtin.name()}", 0o644, parents: true, overwrite: true)?
  }

  # These libraries are folded into libc on musl, but compiler drivers and
  # upstream build systems still commonly link with their conventional names.
  # Keep the aliases as relative symlinks so they do not duplicate libc in the
  # installed root or package archive.
  for lib in ["m", "dl", "rt", "crypt", "pthread"] {
    fs.symlink(p"libc.so", fp"${dest}/usr/lib/lib${lib}.so")?
    fs.symlink(p"libc.a", fp"${dest}/usr/lib/lib${lib}.a")?
  }

  # Clang's musl driver links libssp_nonshared by default. Keep the archive
  # empty: stack protector support is disabled in the toolchain wrapper.
  let ar = process.which("ar")?
  let libssp = p"obj/libssp_nonshared.a"
  run $ar "rcs" $libssp ?
  fs.install(libssp, fp"${dest}/usr/lib/libssp_nonshared.a", 0o644, parents: true, overwrite: true)?

  # Install public headers from include/ (.h.in templates are excluded by the
  # .ext filter; the generated bits/ headers are picked up by recursive walk).
  let include_root = path.absolute(p"include")?

  for e in fs.files(p"include")? |> where .ext == "h" {
    let rel_path = e.path.relative_to(include_root)
    fs.install(e.path, fp"${dest}/usr/include/${rel_path}", 0o644, parents: true, overwrite: true)?
  }

  for bits_dir in [p"arch/generic/bits", fp"arch/${arch}/bits"] {
    let bits_root = path.absolute(bits_dir)?

    for e in fs.files(bits_dir)? |> where .ext == "h" {
      let rel_path = e.path.relative_to(bits_root)
      fs.install(e.path, fp"${dest}/usr/include/bits/${rel_path}", 0o644, parents: true, overwrite: true)?
    }
  }

  # musl installs ld-musl-*.so.1 as a hard link to libc.so. Use a relative
  # symlink in the package so the alias does not duplicate the libc payload.
  # Ship the loader under /usr/lib; baselayout provides /lib -> usr/lib
  # for binaries whose ELF interpreter is /lib/ld-musl-*.so.1.
  var ldso = ""

  if arch == "aarch64" {
    ldso = "ld-musl-aarch64.so.1"
  } else if arch == "x86_64" {
    ldso = "ld-musl-x86_64.so.1"
  }

  if ldso != "" {
    fs.symlink(p"libc.so", fp"${dest}/usr/lib/${ldso}")?
    fs.mkdir(fp"${dest}/usr/bin")?
    fs.remove(fp"${dest}/usr/bin/ldd", missing_ok: true)?

    fs.write(
      fp"${dest}/usr/bin/ldd",
      f"""#!/bin/xsh --
proc main(...argv: List[Str]) [process, error] {{
  unix.exec(process.command_argv("/usr/lib/${ldso}", ["/usr/lib/${ldso}", "--list"].extend(argv)))?
}}

main(@args)?
""",
    )?

    fs.chmod(fp"${dest}/usr/bin/ldd", 0o755)?
  }
}
