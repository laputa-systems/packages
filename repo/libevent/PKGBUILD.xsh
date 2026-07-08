use pm.env as pm_env
use pm.make as make

export let name: Str = "libevent"

export let ver: Str = "2.1.12-stable"

export let rel: Str = "2"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = ["llvm-toolchain", "cmake", "samurai"]

export let sources: List[Path] = [
  p"https://github.com/libevent/libevent/releases/download/release-VERSION/libevent-VERSION.tar.gz",
]

export let checksums: List[Str] = ["92e6de1be9ec176428fd2367677e61ceffc2ee1cb119035037a27d346b0403bb"]

export proc build(dest: Path) [fs, process, env, error] {
  let cmake = process.which("cmake")?
  let samu = process.which("samu")?
  let jobs_flag = f"-j${make.jobs()?}"

  let cmake_args = [
    "-G",
    "Ninja",
    "-B",
    "build",
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DEVENT__LIBRARY_TYPE=SHARED",
    "-DEVENT__DISABLE_OPENSSL=ON",
    "-DEVENT__DISABLE_BENCHMARK=ON",
    "-DEVENT__DISABLE_TESTS=ON",
    "-DEVENT__DISABLE_REGRESS=ON",
    "-DEVENT__DISABLE_SAMPLES=ON",
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
