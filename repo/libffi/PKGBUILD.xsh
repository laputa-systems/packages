use pm.make as make
use pm.util as pm_util

export let name: Str = "libffi"

export let ver: Str = "3.5.2"

export let rel: Str = "3"

export let deps: List[Str] = ["musl", "linux"]

export let mkdeps: List[Str] = ["llvm-toolchain", "linux"]

export let sources: List[Path] = [p"https://github.com/libffi/libffi/releases/download/vVERSION/libffi-VERSION.tar.gz"]

export let checksums: List[Str] = ["f3a3082a23b37c293a4fcd1053147b371f2ff91fa7ea1b2a52e335676bac82dc"]

type LibffiTarget = {target: Str, dir: Str, sources: List[Str]}

pure libffi_target(machine: Str) -> LibffiTarget {
  if machine == "x86_64" {
    return {
      target: "X86_64",
      dir: "x86",
      sources: ["src/x86/ffi64.c", "src/x86/unix64.S", "src/x86/ffiw64.c", "src/x86/win64.S"],
    }
  }

  return {target: "AARCH64", dir: "aarch64", sources: ["src/aarch64/ffi.c", "src/aarch64/sysv.S"]}
}

proc write_generated_headers(target: LibffiTarget) [fs, error] {
  let target_defines = if target.target == "X86_64" {
    """#define HAVE_AS_X86_PCREL 1
#define HAVE_AS_X86_64_UNWIND_SECTION_TYPE 1
"""
  } else {
    ""
  }

  fs.write(
    p"fficonfig.h",
    f"""#ifndef FFICONFIG_H
#define FFICONFIG_H

#define EH_FRAME_FLAGS "a"
#define FFI_EXEC_STATIC_TRAMP 1
#define HAVE_ALLOCA_H 1
#define HAVE_AS_CFI_PSEUDO_OP 1
#define HAVE_DLFCN_H 1
#define HAVE_HIDDEN_VISIBILITY_ATTRIBUTE 1
#define HAVE_INTTYPES_H 1
#define HAVE_LONG_DOUBLE 1
#define HAVE_MEMCPY 1
#define HAVE_MEMFD_CREATE 1
#define HAVE_RO_EH_FRAME 1
#define HAVE_STDINT_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
${target_defines}#define LIBFFI_GNU_SYMBOL_VERSIONING 1
#define LT_OBJDIR ".libs/"
#define PACKAGE "libffi"
#define PACKAGE_BUGREPORT "http://github.com/libffi/libffi/issues"
#define PACKAGE_NAME "libffi"
#define PACKAGE_STRING "libffi ${ver}"
#define PACKAGE_TARNAME "libffi"
#define PACKAGE_URL ""
#define PACKAGE_VERSION "${ver}"
#define SIZEOF_DOUBLE 8
#define SIZEOF_LONG_DOUBLE 16
#define SIZEOF_SIZE_T 8
#define STDC_HEADERS 1
#define VERSION "${ver}"

#ifdef HAVE_HIDDEN_VISIBILITY_ATTRIBUTE
#ifdef LIBFFI_ASM
#ifdef __APPLE__
#define FFI_HIDDEN(name) .private_extern name
#else
#define FFI_HIDDEN(name) .hidden name
#endif
#else
#define FFI_HIDDEN __attribute__ ((visibility ("hidden")))
#endif
#else
#ifdef LIBFFI_ASM
#define FFI_HIDDEN(name)
#else
#define FFI_HIDDEN
#endif
#endif

#endif
""",
  )?

  let ffi_h = p"include/ffi.h.in".read_text()?.replace("@VERSION@", ver).replace("@TARGET@", target.target).replace(
    "@HAVE_LONG_DOUBLE@",
    "1",
  ).replace("@HAVE_LONG_DOUBLE_VARIANT@", "0").replace("@FFI_VERSION_STRING@", ver).replace(
    "@FFI_VERSION_NUMBER@",
    "30502",
  ).replace("@FFI_EXEC_TRAMPOLINE_TABLE@", "0")

  fs.write(p"include/ffi.h", ffi_h)?
  fs.install(fp"src/${target.dir}/ffitarget.h", p"include/ffitarget.h", 0o644, parents: true, overwrite: true)?
}

proc write_version_script() [fs, error] {
  fs.write(
    p"libffi.map",
    """LIBFFI_BASE_8.0 {
  global:
    ffi_type_void;
    ffi_type_uint8;
    ffi_type_sint8;
    ffi_type_uint16;
    ffi_type_sint16;
    ffi_type_uint32;
    ffi_type_sint32;
    ffi_type_uint64;
    ffi_type_sint64;
    ffi_type_float;
    ffi_type_double;
    ffi_type_longdouble;
    ffi_type_pointer;
    ffi_call;
    ffi_prep_cif;
    ffi_prep_cif_var;
    ffi_raw_call;
    ffi_ptrarray_to_raw;
    ffi_raw_to_ptrarray;
    ffi_raw_size;
    ffi_java_raw_call;
    ffi_java_ptrarray_to_raw;
    ffi_java_raw_to_ptrarray;
    ffi_java_raw_size;
    ffi_get_struct_offsets;
  local:
    *;
};

LIBFFI_BASE_8.1 {
  global:
    ffi_get_version;
    ffi_get_version_number;
    ffi_get_default_abi;
    ffi_get_closure_size;
} LIBFFI_BASE_8.0;

LIBFFI_COMPLEX_8.0 {
  global:
    ffi_type_complex_float;
    ffi_type_complex_double;
    ffi_type_complex_longdouble;
} LIBFFI_BASE_8.0;

LIBFFI_CLOSURE_8.0 {
  global:
    ffi_closure_alloc;
    ffi_closure_free;
    ffi_prep_closure;
    ffi_prep_closure_loc;
    ffi_prep_raw_closure;
    ffi_prep_raw_closure_loc;
    ffi_prep_java_raw_closure;
    ffi_prep_java_raw_closure_loc;
} LIBFFI_BASE_8.0;

LIBFFI_GO_CLOSURE_8.0 {
  global:
    ffi_call_go;
    ffi_prep_go_closure;
} LIBFFI_CLOSURE_8.0;
""",
  )?
}

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let arch = pm_util.target_arch()?
  let triple = f"${arch}-linux-musl"
  let target = libffi_target(arch)
  let cflags = ["-O2", "-Wall", "-fexceptions"]
  let defs = ["-DHAVE_CONFIG_H"]
  let includes = ["-I.", "-Iinclude", "-Isrc"]

  let srcs = ["src/prep_cif.c", "src/types.c", "src/raw_api.c", "src/java_raw_api.c", "src/closures.c", "src/tramp.c"].extend(
    target.sources,
  )

  var objs: List[Path] = []
  var tasks: List[make.MakeTask] = []
  var task_deps: List[Str] = []
  write_generated_headers(target)?
  write_version_script()?

  for src in srcs {
    let out = fp"obj/${src.replace("/", "-").replace(".c", "").replace(".S", "")}.lo"
    let task = make.compile_lo_task(cc, triple, cflags, defs, includes, Path.parse(src)?, out)
    tasks = tasks.push(task)
    task_deps = task_deps.push(task.name)
    objs = objs.push(out)
  }

  let so = p"obj/libffi.so.8.2.0"

  tasks = tasks.push(
    make.link_shared_task(cc, triple, objs, "libffi.so.8", ["-Wl,--version-script,libffi.map"], so, task_deps),
  )

  make.run_tasks(tasks, make.jobs()?)?
  fs.install(so, fp"${dest}/usr/lib/libffi.so.8.2.0", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"libffi.so.8.2.0", fp"${dest}/usr/lib/libffi.so.8")?
  fs.symlink(p"libffi.so.8.2.0", fp"${dest}/usr/lib/libffi.so")?
  fs.install(p"include/ffi.h", fp"${dest}/usr/include/ffi.h", 0o644, parents: true, overwrite: true)?
  fs.install(p"include/ffitarget.h", fp"${dest}/usr/include/ffitarget.h", 0o644, parents: true, overwrite: true)?
  fs.mkdir(fp"${dest}/usr/lib/pkgconfig")?

  fs.write(
    fp"${dest}/usr/lib/pkgconfig/libffi.pc",
    f"""prefix=/usr
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libffi
Description: Library supporting Foreign Function Interfaces
Version: ${ver}
Libs: -L\${libdir} -lffi
Cflags: -I\${includedir}
""",
  )?
}
