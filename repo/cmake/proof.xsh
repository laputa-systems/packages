use pm.proof as proof
use pm.util as pm_util

error ScriptError = Failed(kind: Str, message: Str)

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  let cmake = fp"${rootfs}/usr/bin/cmake"
  let samu = fp"${rootfs}/usr/bin/samu"
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

  let os = system.uname()?
  let arch = os.machine
  let ldso = fp"/usr/lib/ld-musl-${arch}.so.1"
  let dynlinker = fp"${rootfs}${ldso.display()}"
  let tmp = fp"${rootfs}/var/tmp/proof-cmake"
  fs.remove(tmp, missing_ok: true)?
  fs.mkdir(tmp)?
  defer fs.remove(tmp, missing_ok: true)?

  fs.write(
    fp"${tmp}/CMakeLists.txt",
    """cmake_minimum_required(VERSION 3.13)
project(hello C)
set(CMAKE_C_STANDARD 99)
add_executable(hello hello.c)
""",
  )?

  fs.write(
    fp"${tmp}/hello.c",
    """#include <stdio.h>
int main(void) { puts("hello cmake"); return 0; }
""",
  )?

  fs.mkdir(fp"${tmp}/build")?

  cd fp"${tmp}/build" {
    let linker_flags = f"-dynamic -Wl,-rpath,/usr/lib -Wl,-dynamic-linker,${dynlinker.display()}"

    var cmake_args: List[Str] = [
      cmake.display(),
      "..",
      "-G",
      "Ninja",
      f"-DCMAKE_MAKE_PROGRAM=${samu.display()}",
      f"-DCMAKE_EXE_LINKER_FLAGS=${linker_flags}",
    ]

    let cmake_proc = process.command_argv(cmake_args[0], cmake_args)
    let cmake_status = process.run(cmake_proc)?

    if ! cmake_status.ok {
      Err(ScriptError.Failed("cmake-proof-configure", "cmake configure failed"))?
    }

    run $samu ?
    let hello = fp"${tmp}/build/hello"
    let out = run.text $dynlinker $hello ?
    let trimmed = out.trim()

    if trimmed != "hello cmake" {
      Err(ScriptError.Failed("cmake-proof", f"unexpected output: ${trimmed}"))?
    }

    print "cmake ok: "${trimmed}
  } ?
}

main(@args)?
