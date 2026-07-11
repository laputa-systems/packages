use pm.env as pm_env
use pm.util as pm_util

export let name = "wayland-libs-client"

export let ver = "1.24.0"

export let rel = "7"

export let deps = ["musl", "libffi", "expat"]

export let mkdeps = ["llvm-toolchain", "muon", "samurai", "pkgconf", "expat", "libffi"]

export let sources = [
  p"https://gitlab.freedesktop.org/wayland/wayland/-/releases/VERSION/downloads/wayland-VERSION.tar.xz",
]

export let checksums = [
  "82892487a01ad67b334eca83b54317a7c86a03a89cfadacfef5211f11a5d0536",
]

export let filetree = [
  {path: p"usr/lib/libwayland-client.so", kind: "symlink"},
  {path: p"usr/lib/libwayland-client.so.0", kind: "symlink"},
  {path: p"usr/lib/libwayland-client.so.0.24.0", kind: "binary"},
]

proc write_embedded_dtd() [fs, error] {
  let dump = p"protocol/wayland.dtd".read_bytes()?.dump("hex-u8")
  var values = []

  for line in dump.split("\n") {
    let words = line.words()
    var index = 1

    while index < words.len() {
      values = values.push(f"0x${words[index]},")
      index += 1
    }
  }

  fs.write(
    p"src/wayland.dtd.h",
    f"""static const char wayland_dtd[] = {{
	${values.join(" ")}
}};
""",
  )?
}

proc patch_python_generator(native_scanner: Str) [fs, error] {
  write_embedded_dtd()?
  let meson_path = p"src/meson.build"
  let text = meson_path.read_text()?

  let patched = text.replace(
    """	prog_embed = find_program('embed.py', native: true)

	embed_dtd = custom_target(
		'wayland.dtd.h',
		input: '../protocol/wayland.dtd',
		output: 'wayland.dtd.h',
		command: [ prog_embed, '@INPUT@', 'wayland_dtd' ],
		capture: true
	)

	wayland_scanner_sources = [ 'scanner.c', embed_dtd ]
""",
    """	wayland_scanner_sources = [ 'scanner.c' ]
""",
  )

  fs.write(meson_path, patched)?
  let root_meson = p"meson.build"

  fs.write(
    root_meson,
    root_meson.read_text()?.replace(
      """	rt_dep = []
	if not cc.has_function('clock_gettime', prefix: '#include <time.h>')
		rt_dep = cc.find_library('rt')
		if not cc.has_function('clock_gettime', prefix: '#include <time.h>', dependencies: rt_dep, args: cc_args)
			error('clock_gettime not found')
		endif
	endif
""",
      """	# musl provides realtime interfaces in libc.
	rt_dep = declare_dependency()
""",
    ),
  )?

  fs.write(
    meson_path,
    meson_path.read_text()?.replace(
      "\tmathlib_dep = cc.find_library('m', required: false)",
      "\tmathlib_dep = declare_dependency(link_args: ['-lm'])",
    ),
  )?

  if native_scanner != "" {
    fs.write(
      meson_path,
      meson_path.read_text()?.replace(
        """if meson.is_cross_build() or not get_option('scanner')
scanner_dep = dependency('wayland-scanner', native: true, version: meson.project_version())
wayland_scanner_for_build = find_program(scanner_dep.get_variable(pkgconfig: 'wayland_scanner'))
else
wayland_scanner_for_build = wayland_scanner
endif
""",
        f"""wayland_scanner_for_build = find_program('${native_scanner}')
""",
      ),
    )?
  }
}

proc build_wayland(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${cpu.count()}"
  let pc = pm_env.pkg_config_context()?
  let build_root = env.get("XSH_PM_BUILD_ROOT") ?? ""

  let native_scanner = if pm_util.build_arch()? != pm_util.target_arch()? and build_root != "" {
    f"${build_root}/usr/bin/wayland-scanner"
  } else {
    ""
  }

  patch_python_generator(native_scanner)?

  env {
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() "-Ddefault_library=shared" "-Ddocumentation=false" "-Ddtd_validation=false" "-Dtests=false" "build" ?

    if native_scanner != "" {
      let native_scanner_path = fp"${fs.cwd()?}/build/wayland-scanner-native"
      let clang = fp"${build_root}/usr/lib/llvm22/bin/clang-22"

      env {
        PATH = f"${build_root}/usr/lib/llvm-toolchain/bin:${build_root}/usr/bin:${env.get("PATH") ?? ""}"
        LD_LIBRARY_PATH = f"${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib"
      } {
        run $clang "-o" $native_scanner_path "src/scanner.c" "src/wayland-util.c" "-Ibuild" "-Ibuild/src" "-Isrc" f"-I${build_root}/usr/include" f"-L${build_root}/usr/lib" f"-Wl,-rpath,${build_root}/usr/lib" "-lexpat" ?
      } ?

      let ninja = p"build/build.ninja"
      let scanner_text = native_scanner_path.display()
      let ninja_text = ninja.read_text()?

      let ninja_text_build_root = ninja_text.replace(
        f" -- ${build_root}/usr/bin/wayland-scanner ",
        f" -- ${scanner_text} ",
      )

      fs.write(ninja, ninja_text_build_root.replace(" -- src/wayland-scanner ", f" -- ${scanner_text} "))?
    }

    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?
}

export proc build(dest: Path) [fs, process, env, error] {
  build_wayland(dest)?

  for entry in fs.ls(fp"${dest}/usr/lib")? {
    if entry.name.starts_with("libwayland-") and ! entry.name.starts_with("libwayland-client.so") {
      fs.remove(entry.path, missing_ok: true)?
    }
  }

  fs.remove(fp"${dest}/usr/bin", missing_ok: true)?
  fs.remove(fp"${dest}/usr/include", missing_ok: true)?
  fs.remove(fp"${dest}/usr/lib/pkgconfig", missing_ok: true)?
  fs.remove(fp"${dest}/usr/share", missing_ok: true)?
}
