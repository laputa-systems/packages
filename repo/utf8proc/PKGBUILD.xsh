use pm.make as make

export let name: Str = "utf8proc"

export let ver: Str = "2.10.0"

export let rel: Str = "2"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = ["llvm-toolchain", "cmake", "samurai"]

export let sources: List[Path] = [p"https://github.com/JuliaStrings/utf8proc/archive/vVERSION.tar.gz"]

export let checksums: List[Str] = ["6f4f1b639daa6dca9f80bc5db1233e9cbaa31a67790887106160b33ef743f136"]

export proc build(dest: Path) [fs, process, env, error] {
  let cmake = process.which("cmake")?
  let samu = process.which("samu")?
  let jobs_flag = f"-j${make.jobs()?}"

  let cmake_args = [
    "-G",
    "Ninja",
    "-B",
    "build",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DBUILD_SHARED_LIBS=ON",
    "-DUTF8PROC_INSTALL=ON",
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
