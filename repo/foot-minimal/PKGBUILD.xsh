use pm.env as pm_env
use pm.make as make
use pm.util as pm_util

export let name = "foot-minimal"

export let ver = "1.27.0"

export let rel = "7"

export let deps = [
  "musl",
  "wayland-libs-client",
  "wayland-libs-cursor",
  "libffi",
  "libxkbcommon",
  "pixman",
  "fontconfig",
  "fcft-minimal",
  "font-ttf-hack",
  "utf8proc",
]

export let mkdeps = [
  "llvm-toolchain",
  "linux",
  "pkgconf",
  "muon",
  "samurai",
  "libffi",
  "wayland-dev",
  "wayland-protocols",
  "libxkbcommon",
  "pixman-dev",
  "fontconfig",
  "fcft-minimal",
  "tllist",
]

export let target_build_deps = ["wayland-dev", "wayland-protocols", "pixman-dev", "tllist"]

export let sources = [
  p"https://codeberg.org/dnkl/foot/archive/VERSION.tar.gz",
  p"files/generated/emoji-variation-sequences.h => generated",
  p"files/generated/foot-terminfo.h => generated",
  p"files/generated/srgb.c => generated",
  p"files/generated/srgb.h => generated",
]

export let checksums = [
  "4e6131cc859ec6a36569f1978cf3617cc3836a681d13d228ded1b4885dab7770",
  "c78138c30e2b89f2ab7f1ed95996696be12f5182b0a3037828438b26d48040ba",
  "a2ff78b72d3b941f05d2a690eaaba4ac7fcb62ce7c599558a4e50a89f8950f76",
  "c038205bf3f77953b6b1125ede9cee8df49d07dd004f9f70f6723f305a06e445",
  "9053596e40a895d310fa3cf74a68ae1f87828d20a3cdcc927275acaf9d2104cc",
]

export let filetree = [
  {path: p"etc/xdg/foot/foot.ini", kind: "file"},
  {path: p"usr/bin/foot", kind: "binary"},
]

proc sysroot_path(root: Str, raw: Str) [fs, error] -> Result[Path] {
  let path_value = fp"${raw.trim()}"

  if fs.exists(path_value)? {
    return path_value
  }

  if root != "" and root != "/" and raw.starts_with("/") {
    return fp"${root}${raw.trim()}"
  }

  path_value
}

proc write_version_header() [fs, error] {
  fs.write(
    p"version.h",
    f"""#define FOOT_VERSION "${ver}"
#define FOOT_MAJOR 1
#define FOOT_MINOR 27
#define FOOT_PATCH 0
#define FOOT_EXTRA ""
""",
  )?
}

proc patch_generated_inputs() [fs, error] {
  fs.install(p"generated/emoji-variation-sequences.h", p"emoji-variation-sequences.h", 0o644, overwrite: true)?
  fs.install(p"generated/foot-terminfo.h", p"foot-terminfo.h", 0o644, overwrite: true)?
  fs.install(p"generated/srgb.c", p"srgb.c", 0o644, overwrite: true)?
  fs.install(p"generated/srgb.h", p"srgb.h", 0o644, overwrite: true)?
  write_version_header()?
  let meson = p"meson.build"
  var text = meson.read_text()?
  text = text.replace("math = cc.find_library('m')", "math = declare_dependency(link_args: ['-lm'])")

  text = text.replace(
    "threads = [dependency('threads'), cc.find_library('stdthreads', required: false)]",
    "threads = [declare_dependency(), cc.find_library('stdthreads', required: false)]",
  )

  text = text.replace(
    """env = find_program('env', native: true)
generate_version_sh = files('generate-version.sh')
version = custom_target(
  'generate_version',
  build_always_stale: true,
  output: 'version.h',
  command: [env, 'LC_ALL=C', generate_version_sh, meson.project_version(), '@CURRENT_SOURCE_DIR@', '@OUTPUT@'])

python = find_program('python3', native: true)
generate_builtin_terminfo_py = files('scripts/generate-builtin-terminfo.py')
foot_terminfo = files('foot.info')
builtin_terminfo = custom_target(
  'generate_builtin_terminfo',
  output: 'foot-terminfo.h',
  command: [python, generate_builtin_terminfo_py,
            '@default_terminfo@', foot_terminfo, 'foot', '@OUTPUT@']
)

generate_emoji_variation_sequences = files('scripts/generate-emoji-variation-sequences.py')
emoji_variation_sequences = custom_target(
  'generate_emoji_variation_sequences',
  input: 'unicode/emoji-variation-sequences.txt',
  output: 'emoji-variation-sequences.h',
  command: [python, generate_emoji_variation_sequences, '@INPUT@', '@OUTPUT@']
)

generate_srgb_funcs = files('scripts/srgb.py')
srgb_funcs = custom_target(
  'generate_srgb_funcs',
  output: ['srgb.c', 'srgb.h'],
  command: [python, generate_srgb_funcs, '@OUTPUT0@', '@OUTPUT1@']
)
""",
    """version = files('version.h')
builtin_terminfo = files('foot-terminfo.h')
emoji_variation_sequences = files('emoji-variation-sequences.h')
srgb_funcs = files('srgb.c', 'srgb.h')
""",
  )

  text = text.replace(
    """executable(
  'footclient',
  'client.c', 'client-protocol.h',
  'foot-features.c', 'foot-features.h',
  'macros.h',
  'util.h',
  version,
  dependencies: [tllist, utf8proc],
  link_with: common,
  install: true)
""",
    """executable(
  'footclient',
  'client.c', 'client-protocol.h',
  'foot-features.c', 'foot-features.h',
  'macros.h',
  'util.h',
  version,
  dependencies: [tllist, utf8proc],
  link_with: common,
  install: false)
""",
  )

  text = text.replace(
    """install_data(
  'foot.desktop', 'foot-server.desktop', 'footclient.desktop',
  install_dir: join_paths(get_option('datadir'), 'applications'))
""",
    "",
  )

  text = text.replace("install_data('foot.ini', install_dir: join_paths(get_option('sysconfdir'), 'xdg', 'foot'))", "")
  text = text.replace("subdir('completions')", "")
  text = text.replace("subdir('icons')", "")
  text = text.replace("subdir('utils')", "")
  fs.write(meson, text)?
}

proc write_minimal_config(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/etc/xdg")?
  fs.mkdir(fp"${dest}/etc/xdg/foot")?

  fs.write(
    fp"${dest}/etc/xdg/foot/foot.ini",
    """font=Hack:size=11
term=xterm-256color
""",
  )?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${make.jobs()?}"
  let pc = pm_env.pkg_config_context()?
  let build_root = env.get("XSH_PM_BUILD_ROOT") ?? ""
  let cross_build = pm_util.build_arch()? != pm_util.target_arch()? and build_root != ""

  let native_tools_ld = if cross_build {
    f"${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib"
  } else {
    pc.ld_library_path
  }

  patch_generated_inputs()?

  env {
    LD_LIBRARY_PATH = native_tools_ld
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() pm_env.meson_sysconfdir_arg() "-Ddefault_library=shared" "-Dwerror=false" "-Ddocs=disabled" "-Dthemes=false" "-Dtests=false" "-Dime=false" "-Dgrapheme-clustering=disabled" "-Dterminfo=disabled" "-Dutmp-backend=none" "build" ?

    if cross_build {
      let ninja = p"build/build.ninja"
      let scanner_text = fp"${build_root}/usr/bin/wayland-scanner".display()
      var ninja_text = ninja.read_text()?
      ninja_text = ninja_text.replace("../../../../root/usr/bin/wayland-scanner", scanner_text)
      ninja_text = ninja_text.replace("../../../../build-root/usr/bin/wayland-scanner", scanner_text)
      ninja_text = ninja_text.replace(f"${build_root}/usr/bin/wayland-scanner", scanner_text)
      fs.write(ninja, ninja_text)?
    }

    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?

  write_minimal_config(dest)?
  fs.remove(fp"${dest}/usr/share", missing_ok: true)?
}
