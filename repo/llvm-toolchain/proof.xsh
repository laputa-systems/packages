use pm.util as pm_util

error ProofError = Failed(kind: Str, message: Str)

proc ensure(condition: Bool, kind: Str, message: Str) [error] {
  if ! condition {
    Err(ProofError.Failed(kind, message))?
  }
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
  ensure(build_root_value != "", "proof-llvm-toolchain", "XSH_PM_BUILD_ROOT is required for native-cross proof")?
  return Path.parse(build_root_value)?
}

proc build_readelf_path() [env, error] -> Result[Path] {
  let build_root = build_root_path()?
  return fp"${build_root}/usr/bin/readelf"
}

proc prove_x86_64_v3() [fs, process, error] {
  let cc = process.which("cc")?
  let objdump = process.which("llvm-objdump")?
  let tmp = fs.temp_dir()?
  defer tmp.remove(missing_ok: true)?

  fs.write(
    fp"${tmp}/v3-toy.c",
    """#include <immintrin.h>

__attribute__((noinline))
void laputa_v3_toy(const unsigned long long *a, const unsigned long long *b, unsigned long long *out, unsigned long long mask) {
  __m256i av = _mm256_loadu_si256((const __m256i *)a);
  __m256i bv = _mm256_loadu_si256((const __m256i *)b);
  __m256i sum = _mm256_add_epi64(av, bv);
  _mm256_storeu_si256((__m256i *)out, sum);
  out[4] = _pdep_u64(out[0], mask);
}
""",
  )?

  let object = fp"${tmp}/v3-toy.o"
  run $cc "-O2" "-c" fp"${tmp}/v3-toy.c" "-o" $object ?

  let asm = run.text $objdump "-d" "--no-show-raw-insn" $object ?
  ensure(asm.contains("vpaddq"), "proof-llvm-toolchain", "x86-64-v3 proof did not emit AVX2 vpaddq")?
  ensure(asm.contains("pdep"), "proof-llvm-toolchain", "x86-64-v3 proof did not emit BMI2 pdep")?
}

proc prove_explicit_aarch64_target() [fs, process, error] {
  let cc = process.which("cc")?
  let readelf = process.which("llvm-readelf")?
  let tmp = fs.temp_dir()?
  defer tmp.remove(missing_ok: true)?

  fs.write(
    fp"${tmp}/aarch64-target-toy.c",
    """int laputa_aarch64_target_toy(void) {
  return 42;
}
""",
  )?

  let object = fp"${tmp}/aarch64-target-toy.o"
  run $cc "-target" "aarch64-linux-gnu" "-O2" "-c" fp"${tmp}/aarch64-target-toy.c" "-o" $object ?

  let header = run.text $readelf "-h" $object ?
  ensure(header.contains("AArch64"), "proof-llvm-toolchain", "explicit aarch64 target did not produce an AArch64 object")?
}

proc prove_target_tools(root: Path, arch: Str) [process, env, error] {
  let readelf = build_readelf_path()?
  let machine = elf_machine_name(arch)
  let cc = fp"${root}/usr/bin/cc"
  let clang = fp"${root}/usr/lib/llvm22/bin/clang-22"
  let cc_header = run.text $readelf "-h" $cc ?
  let clang_header = run.text $readelf "-h" $clang ?
  ensure(cc_header.contains(machine), "proof-llvm-toolchain", f"cc wrapper is not ${arch}")?
  ensure(clang_header.contains(machine), "proof-llvm-toolchain", f"clang-22 is not ${arch}")?
}

proc main(root: Path = /rootfs) [fs, process, env, error] {
  let db = fp"${root}/var/lib/xsh-pm/packages/llvm-toolchain/metadata.json"

  if ! fs.exists(db)? {
    return Err(ProofError.Failed("proof-llvm-toolchain", f"missing package metadata: ${db.display()}"))
  }

  let target_arch = pm_util.target_arch()?
  let build_arch = pm_util.build_arch()?

  if build_arch == target_arch and target_arch == "x86_64" {
    prove_x86_64_v3()?
    prove_explicit_aarch64_target()?
  } else {
    prove_target_tools(root, target_arch)?
  }

  print "llvm-toolchain ok"
}

main(@args)?
