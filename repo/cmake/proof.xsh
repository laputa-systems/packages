##! XSH module `proof` package and build operations.
use pm.proof as proof
use pm.util as pm_util

error ScriptError = Failed(kind: Str, message: Str)

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  let cmake = fp"${rootfs}/usr/bin/cmake"
  proof.target_elf(rootfs, p"usr/bin/cmake", "cmake")?
  proof.target_elf(rootfs, p"usr/bin/cpack", "cpack")?
  proof.target_elf(rootfs, p"usr/bin/ctest", "ctest")?

  if ! fs.exists(fp"${rootfs}/usr/share/cmake/Modules/CMake.cmake")? {
    Err(ScriptError.Failed("cmake-proof", "missing CMake module tree"))?
  }

  if pm_util.build_arch()? != pm_util.target_arch()? {
    print "cmake ok: cross-built "${pm_util.target_arch()?}
    return
  }

  let tmp = fp"${rootfs}/var/tmp/proof-cmake"
  fs.remove(tmp, missing_ok: true)?
  fs.mkdir(tmp)?
  defer fs.remove(tmp, missing_ok: true)?

  # Artifact proofs deliberately compose runtime edges only. `samurai` is a
  # build-host tool, so use this explicit proof-local generator instead of
  # resolving a build dependency through the proof root. It gives CMake the
  # generator capability required for a configure-only package smoke test;
  # `llvm-toolchain` proves compiler execution independently.
  let proof_samu = fp"${tmp}/proof-samu"
  fs.write(
    proof_samu,
    """#!/bin/xsh
proc main(...argv: List[Str]) [] {
  print "1.12.0"
}

main(@args)?
""",
  )?
  fs.chmod(proof_samu, 0o755)?

  fs.write(
    fp"${tmp}/CMakeLists.txt",
    r"""cmake_minimum_required(VERSION 3.13)
project(laputa_cmake_runtime NONE)
file(WRITE "${CMAKE_BINARY_DIR}/proof-output.txt" "cmake runtime closure\n")
""",
  )?

  fs.mkdir(fp"${tmp}/build")?

  cd fp"${tmp}/build" {
    let cmake_args = [
      cmake.display(),
      "..",
      "-G",
      "Ninja",
      f"-DCMAKE_MAKE_PROGRAM=${proof_samu.display()}",
    ]

    let cmake_proc = process.command_argv(cmake_args[0], cmake_args)
    let cmake_status = process.run(cmake_proc)?

    if ! cmake_status.ok {
      Err(ScriptError.Failed("cmake-proof-configure", "cmake configure failed"))?
    }

    let cache = fs.read_text(fp"${tmp}/build/CMakeCache.txt")?
    let marker = fs.read_text(fp"${tmp}/build/proof-output.txt")?

    if ! cache.contains(proof_samu.display()) or marker != "cmake runtime closure\n" {
      Err(ScriptError.Failed("cmake-proof", "configure did not use the isolated runtime proof inputs"))?
    }

    print "cmake ok: runtime configure"
  } ?
}

main(@args)?
