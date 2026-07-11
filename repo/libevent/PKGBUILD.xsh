use pm.env as pm_env
use pm.make as make

export let name = "libevent"

export let ver = "2.1.12-stable"

export let rel = "3"

export let deps = ["musl"]

export let mkdeps = ["llvm-toolchain", "cmake", "samurai"]

export let sources = [p"https://github.com/libevent/libevent/releases/download/release-VERSION/libevent-VERSION.tar.gz"]

export let checksums = ["92e6de1be9ec176428fd2367677e61ceffc2ee1cb119035037a27d346b0403bb"]

proc patch_cmake() [fs, error] {
  let path_value = p"cmake/AddEventLibrary.cmake"

  let text = path_value.read_text()?.replace(
    r"""            add_custom_command(TARGET ${LIB_NAME}_shared
                POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E create_symlink
                    "$<TARGET_FILE_NAME:${LIB_NAME}_shared>"
                    "${LIB_LINK_NAME}"
                WORKING_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}")
""",
    "",
  )

  fs.write(path_value, text)?
}

proc create_unversioned_links() [fs, error] {
  let libdir = p"build/lib"

  for library_name in ["event_core", "event_extra", "event_pthreads", "event"] {
    fs.symlink(fp"lib${library_name}-2.1.so.7.0.1", fp"${libdir}/lib${library_name}.so")?
  }
}

export proc build(dest: Path) [fs, process, env, error] {
  let cmake = process.which("cmake")?
  let samu = process.which("samu")?
  let jobs_flag = f"-j${make.jobs()?}"

  # The upstream helper's WORKING_DIRECTORY makes CMake emit a shell `cd`,
  # which is not available in the package build environment.
  patch_cmake()?

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
  create_unversioned_links()?

  env {
    DESTDIR = dest
  } {
    cd build {
      run $cmake "-P" "cmake_install.cmake" ?
    }
  } ?
}
