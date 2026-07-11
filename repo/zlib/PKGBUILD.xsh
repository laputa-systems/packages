use pm.env as pm_env
use pm.make as make

export let name = "zlib"

export let ver = "1.3.2"

export let rel = "11"

export let deps = ["musl"]

export let mkdeps_host = ["llvm-toolchain", "cmake", "samurai"]

export let sources = [p"https://zlib.net/fossils/zlib-VERSION.tar.gz"]

export let checksums = ["bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16"]

export let filetree = [
  {path: p"usr/include/zconf.h", kind: "file"},
  {path: p"usr/include/zlib.h", kind: "file"},
  {path: p"usr/lib/cmake/zlib/ZLIB-shared-release.cmake", kind: "file"},
  {path: p"usr/lib/cmake/zlib/ZLIB-shared.cmake", kind: "file"},
  {path: p"usr/lib/cmake/zlib/ZLIB-static-release.cmake", kind: "file"},
  {path: p"usr/lib/cmake/zlib/ZLIB-static.cmake", kind: "file"},
  {path: p"usr/lib/cmake/zlib/ZLIBConfig.cmake", kind: "file"},
  {path: p"usr/lib/cmake/zlib/ZLIBConfigVersion.cmake", kind: "file"},
  {path: p"usr/lib/libz.a", kind: "file"},
  {path: p"usr/lib/libz.so", kind: "symlink"},
  {path: p"usr/lib/libz.so.1", kind: "symlink"},
  {path: p"usr/lib/libz.so.1.3.2", kind: "binary"},
  {path: p"usr/lib/pkgconfig/zlib.pc", kind: "file"},
  {path: p"usr/share/doc/zlib/zlib/LICENSE", kind: "file"},
  {path: p"usr/share/doc/zlib/zlib/algorithm.txt", kind: "file"},
  {path: p"usr/share/doc/zlib/zlib/crc-doc.1.0.pdf", kind: "file"},
  {path: p"usr/share/doc/zlib/zlib/rfc1950.txt", kind: "file"},
  {path: p"usr/share/doc/zlib/zlib/rfc1951.txt", kind: "file"},
  {path: p"usr/share/doc/zlib/zlib/rfc1952.txt", kind: "file"},
  {path: p"usr/share/doc/zlib/zlib/txtvsbin.txt", kind: "file"},
  {path: p"usr/share/man/man3/zlib.3", kind: "file"},
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
