use pm.env as pm_env

export let name = "expat"

export let ver = "2.7.3"

export let rel = "7"

export let deps = ["musl"]

export let mkdeps_host = ["llvm-toolchain", "cmake", "samurai"]

export let upstream_sources = [
  {
    source: p"https://github.com/libexpat/libexpat/releases/download/R_2_7_3/expat-VERSION.tar.xz",
    kind: "auto",
    architectures: ["all"],
    checksums: [{arch: "all", sha256: "71df8f40706a7bb0a80a5367079ea75d91da4f8c65c58ec59bcdfbf7decdab9f"}],
  },
]

export let filetree = [
  {path: p"usr/include/expat.h", kind: "file"},
  {path: p"usr/include/expat_config.h", kind: "file"},
  {path: p"usr/include/expat_external.h", kind: "file"},
  {path: p"usr/lib/cmake/expat-2.7.3/expat-config-version.cmake", kind: "file"},
  {path: p"usr/lib/cmake/expat-2.7.3/expat-config.cmake", kind: "file"},
  {path: p"usr/lib/cmake/expat-2.7.3/expat-release.cmake", kind: "file"},
  {path: p"usr/lib/cmake/expat-2.7.3/expat.cmake", kind: "file"},
  {path: p"usr/lib/libexpat.so", kind: "symlink"},
  {path: p"usr/lib/libexpat.so.1", kind: "symlink"},
  {path: p"usr/lib/libexpat.so.1.11.1", kind: "binary"},
  {path: p"usr/lib/pkgconfig/expat.pc", kind: "file"},
  {path: p"usr/share/doc/expat/AUTHORS", kind: "file"},
  {path: p"usr/share/doc/expat/changelog", kind: "file"},
]

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
