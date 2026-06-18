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

proc proof_readelf_path(root: Path) [fs, env, error] -> Result[Path] {
  let target_readelf = fp"${root}/usr/bin/readelf"

  if fs.exists(target_readelf)? {
    return target_readelf
  }

  let build_root = build_root_path()?
  return fp"${build_root}/usr/bin/readelf"
}

proc ensure_file(path_value: Path, label: Str) [fs, error] {
  ensure(fs.exists(path_value)?, "proof-llvm-toolchain", f"missing ${label}: ${path_value.display()}")?
}

proc ensure_executable(path_value: Path, label: Str) [fs, error] {
  ensure_file(path_value, label)?
  let mode = fs.metadata(path_value)?.mode % 4096
  ensure(
    [0o555, 0o755, 0o775, 0o777].contains(mode),
    "proof-llvm-toolchain",
    f"${label} is not executable: ${path_value.display()} mode=${mode}",
  )?
}

proc ensure_xsh_wrapper(path_value: Path, label: Str) [fs, error] {
  ensure_file(path_value, label)?
  let text = fs.read_text(path_value)?
  ensure(text.starts_with("#!/usr/local/bin/xsh"), "proof-llvm-toolchain", f"${label} is not an XSH wrapper")?
  ensure(! text.contains("libgcc"), "proof-llvm-toolchain", f"${label} mentions libgcc")?
  ensure(! text.contains("libstdc++"), "proof-llvm-toolchain", f"${label} mentions libstdc++")?
}

proc prove_tool_linkage(root: Path, readelf: Path, tool: Path) [fs, process, error] {
  ensure_executable(tool, tool.name)?
  let program_headers = run.text $readelf "-l" $tool ?
  ensure(! program_headers.contains("ld-linux"), "proof-llvm-toolchain", f"${tool.display()} uses a glibc interpreter")?

  if program_headers.contains("INTERP") {
    ensure(program_headers.contains("ld-musl"), "proof-llvm-toolchain", f"${tool.display()} does not use a musl interpreter")?
  }

  let dynamic = run.text $readelf "-d" $tool ?
  ensure(! dynamic.contains("libunwind.so"), "proof-llvm-toolchain", f"${tool.display()} needs libunwind.so")?
  ensure(! dynamic.contains("libgcc"), "proof-llvm-toolchain", f"${tool.display()} needs libgcc")?
  ensure(! dynamic.contains("libstdc++"), "proof-llvm-toolchain", f"${tool.display()} needs libstdc++")?
}

proc prove_public_surface(root: Path, arch: Str) [fs, process, env, error] {
  let readelf = proof_readelf_path(root)?
  let bin = fp"${root}/usr/lib/llvm22/bin"

  for wrapper in [
    "cc",
    "clang",
    "c++",
    "clang++",
    "ld",
    "ld.lld",
    "ar",
    "ranlib",
    "nm",
    "objcopy",
    "objdump",
    "readelf",
    "strip",
    "llvm-ar",
    "llvm-ranlib",
    "llvm-nm",
    "llvm-objcopy",
    "llvm-objdump",
    "llvm-readelf",
    "llvm-strip",
  ] {
    ensure_xsh_wrapper(fp"${root}/usr/bin/${wrapper}", wrapper)?
  }

  for tool in [
    "clang",
    "clang++",
    "ld.lld",
    "llvm-ar",
    "llvm-ranlib",
    "llvm-nm",
    "llvm-objcopy",
    "llvm-objdump",
    "llvm-readelf",
    "llvm-strip",
  ] {
    prove_tool_linkage(root, readelf, fp"${bin}/${tool}")?
  }

  ensure_file(fp"${root}/usr/lib/llvm22/lib/clang/22/include/stddef.h", "Clang resource headers")?
  ensure_file(
    fp"${root}/usr/lib/llvm22/lib/clang/22/lib/linux/libclang_rt.builtins-${arch}.a",
    "compiler-rt builtins",
  )?
}

proc prove_default_compile(root: Path, arch: Str) [fs, process, env, error] {
  let machine = elf_machine_name(arch)
  let cc = process.which("cc")?
  let readelf = process.which("llvm-readelf")?
  let tmp = fp"${root}/var/tmp/proof-llvm-toolchain-default"
  fs.remove(tmp, missing_ok: true)?
  fs.mkdir(tmp)?
  defer fs.remove(tmp, missing_ok: true)?

  fs.write(
    fp"${tmp}/default-target.c",
    """int laputa_default_target(void) {
  return 9;
}
""",
  )?

  let object = fp"${tmp}/default-target.o"
  run $cc "-O2" "-c" fp"${tmp}/default-target.c" "-o" $object ?
  let header = run.text $readelf "-h" $object ?
  ensure(header.contains(machine), "proof-llvm-toolchain", f"cc wrapper did not produce a ${arch} object")?
}

proc prove_native_link(root: Path, arch: Str) [fs, process, env, error] {
  let cc = process.which("cc")?
  let readelf = process.which("llvm-readelf")?
  let tmp = fp"${root}/var/tmp/proof-llvm-toolchain-native"
  fs.remove(tmp, missing_ok: true)?
  fs.mkdir(tmp)?
  defer fs.remove(tmp, missing_ok: true)?

  fs.write(
    fp"${tmp}/hello.c",
    """int main(void) {
  return 0;
}
""",
  )?

  let exe = fp"${tmp}/hello"
  run $cc fp"${tmp}/hello.c" "-o" $exe ?
  run $exe ?
  let dynamic = run.text $readelf "-d" $exe ?
  ensure(! dynamic.contains("libunwind"), "proof-llvm-toolchain", "native hello links libunwind")?
  ensure(! dynamic.contains("libgcc"), "proof-llvm-toolchain", "native hello links libgcc")?
  ensure(! dynamic.contains("libstdc++"), "proof-llvm-toolchain", "native hello links libstdc++")?
}

proc prove_native_cxx_link(root: Path, arch: Str) [fs, process, env, error] {
  let cxx = process.which("c++")?
  let readelf = process.which("llvm-readelf")?
  let tmp = fp"${root}/var/tmp/proof-llvm-toolchain-native-cxx"
  fs.remove(tmp, missing_ok: true)?
  fs.mkdir(tmp)?
  defer fs.remove(tmp, missing_ok: true)?

  fs.write(
    fp"${tmp}/hello.cc",
    """#include <string>

int main(void) {
  std::string value = "laputa";
  return value.size() == 6 ? 0 : 1;
}
""",
  )?

  let exe = fp"${tmp}/hello-cxx"
  run $cxx fp"${tmp}/hello.cc" "-o" $exe ?
  run $exe ?
  let dynamic = run.text $readelf "-d" $exe ?
  ensure(! dynamic.contains("libunwind"), "proof-llvm-toolchain", "native C++ hello links libunwind")?
  ensure(! dynamic.contains("libgcc"), "proof-llvm-toolchain", "native C++ hello links libgcc")?
  ensure(! dynamic.contains("libstdc++"), "proof-llvm-toolchain", "native C++ hello links libstdc++")?
}

proc prove_x86_64_v3(root: Path) [fs, process, error] {
  let cc = process.which("cc")?
  let objdump = process.which("llvm-objdump")?
  let tmp = fp"${root}/var/tmp/proof-llvm-toolchain-v3"
  fs.remove(tmp, missing_ok: true)?
  fs.mkdir(tmp)?
  defer fs.remove(tmp, missing_ok: true)?

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

proc prove_explicit_aarch64_target(root: Path) [fs, process, error] {
  let cc = process.which("cc")?
  let readelf = process.which("llvm-readelf")?
  let tmp = fp"${root}/var/tmp/proof-llvm-toolchain-aarch64"
  fs.remove(tmp, missing_ok: true)?
  fs.mkdir(tmp)?
  defer fs.remove(tmp, missing_ok: true)?

  fs.write(
    fp"${tmp}/aarch64-target-toy.c",
    """int laputa_aarch64_target_toy(void) {
  return 42;
}
""",
  )?

  let object = fp"${tmp}/aarch64-target-toy.o"
  run $cc "-target" "aarch64-linux-musl" "-O2" "-c" fp"${tmp}/aarch64-target-toy.c" "-o" $object ?
  let header = run.text $readelf "-h" $object ?

  ensure(
    header.contains("AArch64"),
    "proof-llvm-toolchain",
    "explicit aarch64 target did not produce an AArch64 object",
  )?
}

proc prove_target_tools(root: Path, arch: Str) [fs, process, env, error] {
  let readelf = proof_readelf_path(root)?
  let machine = elf_machine_name(arch)
  let cc = fp"${root}/usr/bin/cc"
  let clang = fp"${root}/usr/lib/llvm22/bin/clang"
  let clang_header = run.text $readelf "-h" $clang ?
  ensure(clang_header.contains(machine), "proof-llvm-toolchain", f"clang is not ${arch}")?

  let cc_text = fs.read_text(cc)?
  ensure(cc_text.starts_with("#!/usr/local/bin/xsh"), "proof-llvm-toolchain", "cc wrapper is not an XSH script")?

  let tmp = fp"${root}/var/tmp/proof-llvm-toolchain-wrapper"
  fs.remove(tmp, missing_ok: true)?
  fs.mkdir(tmp)?
  defer fs.remove(tmp, missing_ok: true)?

  fs.write(
    fp"${tmp}/wrapper-target.c",
    """int laputa_wrapper_target(void) {
  return 7;
}
""",
  )?

  let object = fp"${tmp}/wrapper-target.o"
  run $cc "-O2" "-c" fp"${tmp}/wrapper-target.c" "-o" $object ?
  let object_header = run.text $readelf "-h" $object ?
  ensure(object_header.contains(machine), "proof-llvm-toolchain", f"cc wrapper did not produce a ${arch} object")?
}

proc main(root: Path = /rootfs) [fs, process, env, error] {
  let db = fp"${root}/var/lib/xsh-pm/packages/llvm-toolchain/metadata.json"

  if ! fs.exists(db)? {
    return Err(ProofError.Failed("proof-llvm-toolchain", f"missing package metadata: ${db.display()}"))
  }

  let target_arch = pm_util.target_arch()?
  let build_arch = pm_util.build_arch()?
  prove_public_surface(root, target_arch)?
  prove_default_compile(root, target_arch)?

  if build_arch == target_arch and target_arch == "x86_64" {
    prove_x86_64_v3(root)?
    prove_explicit_aarch64_target(root)?
    prove_native_link(root, target_arch)?
    prove_native_cxx_link(root, target_arch)?
  } else if build_arch == target_arch {
    prove_explicit_aarch64_target(root)?
    prove_native_link(root, target_arch)?
    prove_native_cxx_link(root, target_arch)?
  } else {
    prove_target_tools(root, target_arch)?
  }

  print "llvm-toolchain ok"
}

main(@args)?
