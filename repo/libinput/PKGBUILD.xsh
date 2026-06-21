use pm.meson as pm_meson
use pm.util as pm_util

export let name: Str = "libinput"

export let ver: Str = "1.31.2"

export let rel: Str = "3"

export let deps: List[Str] = ["musl", "libudev-zero", "libevdev", "mtdev"]

export let mkdeps: List[Str] = ["llvm-toolchain", "linux", "muon", "pkgconf", "libudev-zero", "libevdev", "mtdev"]

export let sources: List[Path] = [
  p"https://gitlab.freedesktop.org/libinput/libinput/-/archive/VERSION/libinput-VERSION.tar.gz",
]

export let checksums: List[Str] = ["507a40b8a74568ed7c2bd05acf2e15ee3d9f4703102dca86d4f6a804e73bf1f6"]

proc patch_python_tools() [fs, env, error] {
  let meson = p"meson.build"
  var text = meson.read_text()?
  let target_root = env.get("LAPUTA_ROOT") ?? "/"
  let target_arch = pm_util.target_arch()?
  let builtins = f"${target_root}/usr/lib/libclang_rt.builtins-${target_arch}.a"

  let compiler_rt_dep = if target_root != "" and target_root != "/" {
    f"declare_dependency(link_args: ['${builtins}'])"
  } else {
    "declare_dependency()"
  }

  text = text.replace(
    """src_python_tools = files(
	'tools/libinput-analyze-buttons.py',
	'tools/libinput-analyze-per-slot-delta.py',
	'tools/libinput-analyze-recording.py',
	'tools/libinput-analyze-touch-down-state.py',
	'tools/libinput-list-kernel-devices.py',
	'tools/libinput-measure-fuzz.py',
	'tools/libinput-measure-touchpad-size.py',
	'tools/libinput-measure-touchpad-tap.py',
	'tools/libinput-measure-touchpad-pressure.py',
	'tools/libinput-measure-touch-size.py',
	'tools/libinput-replay.py'
)

foreach t : src_python_tools
	configure_file(input: t,
		       output: '@BASENAME@',
		       copy: true,
		       install_dir : libinput_tool_path
		      )
endforeach
""",
    "",
  )

  text = text.replace(
    "dep_lm = cc.find_library('m', required : false)",
    """# musl packages libm as a libc symlink; link by name instead of recording the build-env path.
dep_lm = declare_dependency(link_args: ['-lm'])""",
  )

  text = text.replace(
    "dep_rt = cc.find_library('rt', required : false)",
    f"""# musl provides realtime interfaces in libc; avoid recording the build-env librt.
dep_rt = declare_dependency()
dep_compiler_rt = ${compiler_rt_dep}""",
  )

  text = text.replace(
    """# test including from C++ (in case CPP compiler is available)
if add_languages('cpp', native: false, required: false)
	executable('test-build-cxx',
		   'test/build-cxx.cc',
		   dependencies : [dep_udev],
		   include_directories : [includes_src, includes_include],
		   install : false)
endif
""",
    "",
  )

  fs.write(meson, text)?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${cpu.count()}"
  let pc = pm_meson.pkg_config_env()?
  let target_root = env.get("LAPUTA_ROOT") ?? "/"
  let target_arch = pm_util.target_arch()?
  let builtins = f"${target_root}/usr/lib/libclang_rt.builtins-${target_arch}.a"
  patch_python_tools()?

  env {
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" "-Dprefix=/usr" "-Dlibdir=lib" "-Dlibexecdir=libexec" "-Ddefault_library=shared" "-Ddocumentation=false" "-Dlibwacom=false" "-Ddebug-gui=false" "-Dtests=false" "-Dinstall-tests=false" "-Dmtdev=true" "-Dzshcompletiondir=no" "-Dlua-plugins=disabled" "-Dautoload-plugins=false" "build" ?

    if target_root != "" and target_root != "/" {
      let ninja = p"build/build.ninja"
      fs.write(ninja, ninja.read_text()?.replace(" -Wl,--end-group", f" -Wl,--end-group ${builtins}"))?
    }

    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest.display()
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?

  fs.remove(fp"${dest}/usr/share/man", missing_ok: true)?
}
