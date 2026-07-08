use pm.env as pm_env
use pm.make as make

export let name: Str = "libpng"

export let ver: Str = "1.6.50"

export let rel: Str = "2"

export let deps: List[Str] = ["musl", "zlib"]

export let mkdeps: List[Str] = ["llvm-toolchain", "cmake", "samurai", "zlib"]

export let sources: List[Path] = [p"https://download.sourceforge.net/libpng/libpng-VERSION.tar.xz"]

export let checksums: List[Str] = ["4df396518620a7aa3651443e87d1b2862e4e88cad135a8b93423e01706232307"]

export proc build(dest: Path) [fs, process, env, error] {
  let cmake = process.which("cmake")?
  let samu = process.which("samu")?
  let jobs_flag = f"-j${make.jobs()?}"

  var cmake_args: List[Str] = [
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

  fs.remove(fp"${dest}/usr/bin", missing_ok: true)?
  fs.remove(fp"${dest}/usr/share/man", missing_ok: true)?
}
