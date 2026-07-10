use pm.env as pm_env
use pm.make as make

export let name = "zlib"

export let ver = "1.3.2"

export let rel = "6"

export let deps = ["musl"]

export let mkdeps = ["llvm-toolchain", "cmake", "samurai"]

export let sources = [p"https://zlib.net/fossils/zlib-VERSION.tar.gz"]

export let checksums = [
  "bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16",
]

export proc build(dest: Path) [fs, process, env, error] {
  let cmake = process.which("cmake")?
  let samu = process.which("samu")?
  let jobs = make.jobs()?
  let jobs_flag = f"-j${jobs}"

  let cmake_args = [
    "-G",
    "Ninja",
    "-B",
    "build",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DBUILD_SHARED_LIBS=ON",
    "-DZLIB_BUILD_TESTING=OFF",
    pm_env.cmake_install_prefix_arg(),
    pm_env.cmake_install_libdir_arg(),
  ]

  run $cmake ${cmake_args} ?
  run $samu "-C" "build" $jobs_flag ?

  env {
    DESTDIR = dest
  } {
    cd build {
      run $cmake "-P" "cmake_install.cmake" ?
    }
  } ?
}
