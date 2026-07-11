use pm.env as pm_env
use pm.make as make

export let name = "libevent"

export let ver = "2.1.12-stable"

export let rel = "6"

export let deps = ["musl"]

export let mkdeps = ["llvm-toolchain", "cmake", "samurai"]

export let sources = [p"https://github.com/libevent/libevent/releases/download/release-VERSION/libevent-VERSION.tar.gz"]

export let checksums = ["92e6de1be9ec176428fd2367677e61ceffc2ee1cb119035037a27d346b0403bb"]

export let filetree = [
  {path: p"usr/bin/event_rpcgen.py", kind: "file"},
  {path: p"usr/include/evdns.h", kind: "file"},
  {path: p"usr/include/event.h", kind: "file"},
  {path: p"usr/include/event2/buffer.h", kind: "file"},
  {path: p"usr/include/event2/buffer_compat.h", kind: "file"},
  {path: p"usr/include/event2/bufferevent.h", kind: "file"},
  {path: p"usr/include/event2/bufferevent_compat.h", kind: "file"},
  {path: p"usr/include/event2/bufferevent_struct.h", kind: "file"},
  {path: p"usr/include/event2/dns.h", kind: "file"},
  {path: p"usr/include/event2/dns_compat.h", kind: "file"},
  {path: p"usr/include/event2/dns_struct.h", kind: "file"},
  {path: p"usr/include/event2/event-config.h", kind: "file"},
  {path: p"usr/include/event2/event.h", kind: "file"},
  {path: p"usr/include/event2/event_compat.h", kind: "file"},
  {path: p"usr/include/event2/event_struct.h", kind: "file"},
  {path: p"usr/include/event2/http.h", kind: "file"},
  {path: p"usr/include/event2/http_compat.h", kind: "file"},
  {path: p"usr/include/event2/http_struct.h", kind: "file"},
  {path: p"usr/include/event2/keyvalq_struct.h", kind: "file"},
  {path: p"usr/include/event2/listener.h", kind: "file"},
  {path: p"usr/include/event2/rpc.h", kind: "file"},
  {path: p"usr/include/event2/rpc_compat.h", kind: "file"},
  {path: p"usr/include/event2/rpc_struct.h", kind: "file"},
  {path: p"usr/include/event2/tag.h", kind: "file"},
  {path: p"usr/include/event2/tag_compat.h", kind: "file"},
  {path: p"usr/include/event2/thread.h", kind: "file"},
  {path: p"usr/include/event2/util.h", kind: "file"},
  {path: p"usr/include/event2/visibility.h", kind: "file"},
  {path: p"usr/include/evhttp.h", kind: "file"},
  {path: p"usr/include/evrpc.h", kind: "file"},
  {path: p"usr/include/evutil.h", kind: "file"},
  {path: p"usr/lib/cmake/libevent/LibeventConfig.cmake", kind: "file"},
  {path: p"usr/lib/cmake/libevent/LibeventConfigVersion.cmake", kind: "file"},
  {path: p"usr/lib/cmake/libevent/LibeventTargets-shared-release.cmake", kind: "file"},
  {path: p"usr/lib/cmake/libevent/LibeventTargets-shared.cmake", kind: "file"},
  {path: p"usr/lib/libevent-2.1.so", kind: "symlink"},
  {path: p"usr/lib/libevent-2.1.so.7", kind: "symlink"},
  {path: p"usr/lib/libevent-2.1.so.7.0.1", kind: "binary"},
  {path: p"usr/lib/libevent.so", kind: "symlink"},
  {path: p"usr/lib/libevent_core-2.1.so", kind: "symlink"},
  {path: p"usr/lib/libevent_core-2.1.so.7", kind: "symlink"},
  {path: p"usr/lib/libevent_core-2.1.so.7.0.1", kind: "binary"},
  {path: p"usr/lib/libevent_core.so", kind: "symlink"},
  {path: p"usr/lib/libevent_extra-2.1.so", kind: "symlink"},
  {path: p"usr/lib/libevent_extra-2.1.so.7", kind: "symlink"},
  {path: p"usr/lib/libevent_extra-2.1.so.7.0.1", kind: "binary"},
  {path: p"usr/lib/libevent_extra.so", kind: "symlink"},
  {path: p"usr/lib/libevent_pthreads-2.1.so", kind: "symlink"},
  {path: p"usr/lib/libevent_pthreads-2.1.so.7", kind: "symlink"},
  {path: p"usr/lib/libevent_pthreads-2.1.so.7.0.1", kind: "binary"},
  {path: p"usr/lib/libevent_pthreads.so", kind: "symlink"},
  {path: p"usr/lib/pkgconfig/libevent.pc", kind: "file"},
  {path: p"usr/lib/pkgconfig/libevent_core.pc", kind: "file"},
  {path: p"usr/lib/pkgconfig/libevent_extra.pc", kind: "file"},
  {path: p"usr/lib/pkgconfig/libevent_pthreads.pc", kind: "file"},
]

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
