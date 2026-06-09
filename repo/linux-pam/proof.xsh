use pm.util as pm_util

error LinuxPamProofError = Failed(kind: Str, message: Str)

proc ensure(condition: Bool, kind: Str, message: Str) [error] {
  if ! condition {
    Err(LinuxPamProofError.Failed(kind, message))?
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
  ensure(build_root_value != "", "proof-linux-pam", "XSH_PM_BUILD_ROOT is required for native-cross proof")?
  return Path.parse(build_root_value)?
}

proc cross_cc(default_cc: Path, build_arch: Str, target_arch: Str) [env, error] -> Result[Path] {
  if build_arch == target_arch {
    return default_cc
  }

  let build_root = build_root_path()?
  return fp"${build_root}/usr/lib/llvm22/bin/clang-22"
}

proc readelf_path(default_readelf: Path, build_arch: Str, target_arch: Str) [env, error] -> Result[Path] {
  if build_arch == target_arch {
    return default_readelf
  }

  let build_root = build_root_path()?
  return fp"${build_root}/usr/bin/readelf"
}

proc compile_smoke(cc: Path, rootfs: Path, source: Path, bin: Path, triple: Str, ldso: Path, build_arch: Str, target_arch: Str) [process, env, error] {
  let include_dir = fp"${rootfs}/usr/include"
  let lib_dir = fp"${rootfs}/usr/lib"

  if build_arch == target_arch {
    run $cc f"--target=${triple}" f"--sysroot=${rootfs.display()}" "-dynamic" f"-I${include_dir.display()}" f"-L${lib_dir.display()}" f"-Wl,-rpath,${lib_dir.display()}" f"-Wl,-dynamic-linker,${ldso.display()}" $source "-lpam" "-o" $bin ?
    return
  }

  let build_root = build_root_path()?

  env {
    LD_LIBRARY_PATH = f"${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib"
    PATH = f"${build_root}/usr/lib/llvm-toolchain/bin:${build_root}/usr/bin:${env.get("PATH") ?? ""}"
  } {
    run $cc f"--target=${triple}" f"--sysroot=${rootfs.display()}" "-fuse-ld=lld" "-nostdlib" fp"${lib_dir}/Scrt1.o" fp"${lib_dir}/crti.o" $source f"-L${lib_dir.display()}" "-lpam" "-lc" fp"${lib_dir}/crtn.o" f"-Wl,-rpath,${lib_dir.display()}" f"-Wl,-dynamic-linker,${ldso.display()}" "-o" $bin ?
  } ?
}

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  let arch = pm_util.target_arch()?
  let build_arch = pm_util.build_arch()?
  let triple = f"${arch}-linux-musl"
  let ldso = fp"${rootfs}/usr/lib/${musl_ldso_name(arch)}"
  let default_cc = process.which("cc")?
  let cc = cross_cc(default_cc, build_arch, arch)?
  let default_readelf = process.which("readelf")?
  let readelf = readelf_path(default_readelf, build_arch, arch)?
  let tmp = fs.temp_dir()?
  defer tmp.remove(missing_ok: true)?

  fs.write(
    fp"${tmp}/pam-smoke.c",
    """#include <security/pam_appl.h>
#include <stdio.h>
int main(void) {
  const char *msg = pam_strerror(0, PAM_SUCCESS);
  puts(msg ? msg : "pam ok");
  return 0;
}
""",
  )?

  let bin = fp"${tmp}/pam-smoke"
  compile_smoke(cc, rootfs, fp"${tmp}/pam-smoke.c", bin, triple, ldso, build_arch, arch)?

  let header = run.text $readelf "-h" $bin ?
  ensure(header.contains(elf_machine_name(arch)), "proof-linux-pam", f"pam smoke binary is not ${arch}")?

  if build_arch == arch {
    let out = run.text $ldso $bin ?

    if out.trim() == "" {
      return Err(LinuxPamProofError.Failed("proof-linux-pam", "pam smoke produced no output"))
    }

    print "linux-pam ok"
  } else {
    print "linux-pam ok: cross-built "${arch}
  }
}

main(@args)?
