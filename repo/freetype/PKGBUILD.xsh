use pm.make as make

export let name: Str = "freetype"

export let ver: Str = "2.14.1"

export let rel: Str = "2"

export let deps: List[Str] = ["musl", "zlib", "libpng"]

export let mkdeps: List[Str] = ["llvm-toolchain", "cmake", "samurai", "pkgconf", "zlib", "libpng"]

export let sources: List[Path] = [p"https://download-mirror.savannah.gnu.org/releases/freetype/freetype-VERSION.tar.xz"]

export let checksums: List[Str] = ["32427e8c471ac095853212a37aef816c60b42052d4d9e48230bab3bdf2936ccc"]

export proc build(dest: Path) [fs, process, env, error] {
  let cmake = process.which("cmake")?
  let samu = process.which("samu")?
  let jobs_flag = f"-j${make.jobs()?}"
  let target_root = env.get("LAPUTA_ROOT") ?? "/"

  var cmake_args = [
    "-S",
    ".",
    "-B",
    "build",
    "-G",
    "Ninja",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_INSTALL_PREFIX=/usr",
    "-DCMAKE_INSTALL_LIBDIR=lib",
    "-DBUILD_SHARED_LIBS=ON",
    "-DFT_REQUIRE_ZLIB=ON",
    "-DFT_REQUIRE_PNG=ON",
    "-DFT_DISABLE_BZIP2=ON",
    "-DFT_DISABLE_BROTLI=ON",
    "-DFT_DISABLE_HARFBUZZ=ON",
  ]

  if target_root != "" and target_root != "/" {
    cmake_args = cmake_args.extend([
      f"-DZLIB_LIBRARY=${target_root}/usr/lib/libz.so",
      f"-DZLIB_INCLUDE_DIR=${target_root}/usr/include",
      f"-DPNG_LIBRARY=${target_root}/usr/lib/libpng.so",
      f"-DPNG_PNG_INCLUDE_DIR=${target_root}/usr/include",
    ])
  }

  run $cmake @cmake_args ?
  run $samu "-C" "build" $jobs_flag ?

  env {
    DESTDIR = dest.display()
  } {
    run $samu "-C" "build" "install" ?
  } ?

  fs.remove(fp"${dest}/usr/share/aclocal", missing_ok: true)?
  fs.remove(fp"${dest}/usr/share/man", missing_ok: true)?
}
