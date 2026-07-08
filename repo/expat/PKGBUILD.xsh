use pm.env as pm_env
export let name: Str = "expat"

export let ver: Str = "2.7.3"

export let rel: Str = "2"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = ["llvm-toolchain", "cmake", "samurai"]

export let sources: List[Path] = [
  p"https://github.com/libexpat/libexpat/releases/download/R_2_7_3/expat-VERSION.tar.xz",
]

export let checksums: List[Str] = ["71df8f40706a7bb0a80a5367079ea75d91da4f8c65c58ec59bcdfbf7decdab9f"]

export proc build(dest: Path) [fs, process, env, error] {
  let cmake = process.which("cmake")?
  let samu = process.which("samu")?
  let jobs_flag = f"-j${cpu.count()}"

  let cmake_args = [
    "-S",
    ".",
    "-B",
    "build",
    "-G",
    "Ninja",
    "-DCMAKE_BUILD_TYPE=Release",
    pm_env.cmake_install_prefix_arg(),
    pm_env.cmake_install_libdir_arg(),
    "-DEXPAT_BUILD_DOCS=OFF",
    "-DEXPAT_BUILD_EXAMPLES=OFF",
    "-DEXPAT_BUILD_FUZZERS=OFF",
    "-DEXPAT_BUILD_PKGCONFIG=ON",
    "-DEXPAT_BUILD_TESTS=OFF",
    "-DEXPAT_BUILD_TOOLS=OFF",
    "-DEXPAT_SHARED_LIBS=ON",
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

  fs.remove(fp"${dest}/usr/lib/libexpat.a", missing_ok: true)?
}
