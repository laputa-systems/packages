use pm.make as make

export let name: Str = "zlib"

export let ver: Str = "1.3.2"

export let rel: Str = "6"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = ["llvm-toolchain", "cmake", "samurai"]

export let sources: List[Path] = [p"https://zlib.net/fossils/zlib-VERSION.tar.gz"]

export let checksums: List[Str] = ["bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16"]

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
    "-DCMAKE_INSTALL_PREFIX=/usr",
    "-DCMAKE_INSTALL_LIBDIR=lib",
  ]

  run $cmake ${cmake_args} ?
  run $samu "-C" "build" $jobs_flag ?

  env {
    DESTDIR = dest.display()
  } {
    run $samu "-C" "build" "install" ?
  } ?
}
