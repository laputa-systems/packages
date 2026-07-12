use pm.env as pm_env
use pm.make as make

export let name = "libpng"

export let ver = "1.6.50"

export let rel = "9"

export let deps = ["musl", "zlib"]

export let mkdeps_host = ["llvm-toolchain", "cmake", "samurai", "zlib"]

export let upstream_sources = [
  {
    source: p"https://download.sourceforge.net/libpng/libpng-VERSION.tar.xz",
    kind: "auto",
    architectures: ["all"],
    checksums: [{arch: "all", sha256: "4df396518620a7aa3651443e87d1b2862e4e88cad135a8b93423e01706232307"}],
  },
]

export let filetree = [
  {path: p"usr/include/libpng16/png.h", kind: "file"},
  {path: p"usr/include/libpng16/pngconf.h", kind: "file"},
  {path: p"usr/include/libpng16/pnglibconf.h", kind: "file"},
  {path: p"usr/include/png.h", kind: "file"},
  {path: p"usr/include/pngconf.h", kind: "file"},
  {path: p"usr/include/pnglibconf.h", kind: "file"},
  {path: p"usr/lib/cmake/PNG/PNGConfig.cmake", kind: "file"},
  {path: p"usr/lib/cmake/PNG/PNGConfigVersion.cmake", kind: "file"},
  {path: p"usr/lib/cmake/PNG/PNGTargets-release.cmake", kind: "file"},
  {path: p"usr/lib/cmake/PNG/PNGTargets.cmake", kind: "file"},
  {path: p"usr/lib/libpng.so", kind: "symlink"},
  {path: p"usr/lib/libpng/libpng16-release.cmake", kind: "file"},
  {path: p"usr/lib/libpng/libpng16.cmake", kind: "file"},
  {path: p"usr/lib/libpng16.so", kind: "symlink"},
  {path: p"usr/lib/libpng16.so.16", kind: "symlink"},
  {path: p"usr/lib/libpng16.so.16.50.0", kind: "binary"},
  {path: p"usr/lib/pkgconfig/libpng.pc", kind: "symlink"},
  {path: p"usr/lib/pkgconfig/libpng16.pc", kind: "file"},
]

export proc build(dest: Path) [fs, process, env, error] {
  let cmake = process.which("cmake")?
  let samu = process.which("samu")?
  let jobs_flag = f"-j${make.jobs()?}"

  # CMake's legacy post-build symlink command fails under the XSH build root.
  # Install the unversioned development link after CMake installs the library.
  var cmake_lists = p"CMakeLists.txt".read_text()?

  cmake_lists = cmake_lists.replace(
    r"""      create_symlink(libpng${CMAKE_SHARED_LIBRARY_SUFFIX} TARGET png_shared)
      install(FILES "$<TARGET_LINKER_FILE_DIR:png_shared>/libpng${CMAKE_SHARED_LIBRARY_SUFFIX}"
              DESTINATION "${CMAKE_INSTALL_LIBDIR}")
""",
    "",
  )

  fs.write(p"CMakeLists.txt", cmake_lists)?

  var cmake_args = [
    "-S",
    ".",
    "-B",
    "build",
    "-G",
    "Ninja",
    "-DCMAKE_BUILD_TYPE=Release",
    pm_env.cmake_install_prefix_arg(),
    pm_env.cmake_install_libdir_arg(),
    "-DPNG_SHARED=ON",
    "-DPNG_STATIC=OFF",
    "-DPNG_TESTS=OFF",
    "-DPNG_TOOLS=OFF",
    "-DPNG_EXECUTABLES=OFF",
  ]

  let target_root = env.get("LAPUTA_ROOT") ?? "/"

  if target_root != "" and target_root != "/" {
    cmake_args = cmake_args.push(f"-DZLIB_ROOT=${target_root}/usr")
    cmake_args = cmake_args.push(f"-DZLIB_LIBRARY=${target_root}/usr/lib/libz.so")
    cmake_args = cmake_args.push(f"-DZLIB_INCLUDE_DIR=${target_root}/usr/include")
  }

  run $cmake @cmake_args ?
  run $samu "-C" "build" $jobs_flag ?

  env {
    DESTDIR = dest
  } {
    cd build {
      run $cmake "-P" "cmake_install.cmake" ?
    }
  } ?

  fs.symlink(p"libpng16.so", fp"${dest}/usr/lib/libpng.so")?
  fs.remove(fp"${dest}/usr/bin", missing_ok: true)?
  fs.remove(fp"${dest}/usr/share/man", missing_ok: true)?
}
