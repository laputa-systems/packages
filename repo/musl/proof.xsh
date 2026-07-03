use pm.util as pm_util

error ScriptError = Failed(kind: Str, message: Str)

proc ensure(condition: Bool, kind: Str, message: Str) [error] {
  if ! condition {
    Err(ScriptError.Failed(kind, message))?
  }
}

pure musl_ldso_name(arch: Str) -> Str {
  if arch == "aarch64" {
    return "ld-musl-aarch64.so.1"
  }

  return f"ld-musl-${arch}.so.1"
}

pure elf_machine_name(arch: Str) -> Str {
  if arch == "aarch64" {
    return "AArch64"
  }

  if arch == "x86_64" {
    return "X86-64"
  }

  return arch
}

proc build_root_path() [env, error] -> Result[Path] {
  let build_root_value = (env.get("XSH_PM_BUILD_ROOT") ?? "").trim()
  ensure(build_root_value != "", "proof-musl", "XSH_PM_BUILD_ROOT is required for native-cross proof")?
  return fp"${build_root_value}"
}

proc cross_cc(default_cc: Path, build_arch: Str, target_arch: Str) [env, error] -> Result[Path] {
  if build_arch == target_arch {
    return default_cc
  }

  let build_root = build_root_path()?
  return fp"${build_root}/usr/lib/llvm22/bin/clang-22"
}

proc compile_hello(
  cc: Path,
  rootfs: Path,
  hello_src: Path,
  hello: Path,
  triple: Str,
  dynlinker: Path,
  build_arch: Str,
  target_arch: Str,
) [process, env, error] {
  let include_dir = fp"${rootfs}/usr/include"
  let lib_dir = fp"${rootfs}/usr/lib"

  if build_arch == target_arch {
    run $cc f"--target=${triple}" f"--sysroot=${rootfs.display()}" "-dynamic" f"-I${include_dir.display()}" f"-L${lib_dir.display()}" f"-Wl,-rpath,${lib_dir.display()}" f"-Wl,-dynamic-linker,${dynlinker.display()}" $hello_src "-o" $hello ?
    return
  }

  let build_root = build_root_path()?

  env {
    LD_LIBRARY_PATH = f"${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib"
    PATH = f"${build_root}/usr/lib/llvm-toolchain/bin:${build_root}/usr/bin:${env.get("PATH") ?? ""}"
  } {
    run $cc f"--target=${triple}" f"--sysroot=${rootfs.display()}" "-fuse-ld=lld" "-nostdlib" fp"${lib_dir}/Scrt1.o" fp"${lib_dir}/crti.o" $hello_src f"-L${lib_dir.display()}" "-lc" fp"${lib_dir}/crtn.o" f"-Wl,-rpath,${lib_dir.display()}" f"-Wl,-dynamic-linker,${dynlinker.display()}" "-o" $hello ?
  } ?
}

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  let arch = pm_util.target_arch()?
  let build_arch = pm_util.build_arch()?
  let triple = f"${arch}-linux-musl"
  let ldso = musl_ldso_name(arch)
  let default_cc = process.which("cc")?
  let cc = cross_cc(default_cc, build_arch, arch)?
  let readelf = process.which("readelf")?
  let tmp = fp"${rootfs}/var/tmp/proof-musl"
  fs.remove(tmp, missing_ok: true)?
  fs.mkdir(tmp)?
  defer fs.remove(tmp, missing_ok: true)?
  let hello_src = fp"${tmp}/hello.c"

  fs.write(
    hello_src,
    """#include <stdio.h>
int main(void) { puts("hello musl"); return 0; }
""",
  )?

  let hello = fp"${tmp}/hello"
  let dynlinker = fp"${rootfs}/usr/lib/${ldso}"
  compile_hello(cc, rootfs, hello_src, hello, triple, dynlinker, build_arch, arch)?
  let header = run.text $readelf "-h" $hello ?
  ensure(header.contains(elf_machine_name(arch)), "proof-musl", f"hello binary is not ${arch}")?

  if build_arch == arch {
    let out = run.text $dynlinker $hello ?
    let trimmed = out.trim()

    if trimmed != "hello musl" {
      return Err(ScriptError.Failed("proof-musl", f"unexpected output: ${trimmed}"))?
    }

    print "musl ok: "${trimmed}
  } else {
    print "musl ok: cross-built "${arch}
  }
}

main(@args)?
