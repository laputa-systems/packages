use pm.env as pm_env

export let name = "wayland-protocols"

export let ver = "1.45"

export let rel = "5"

export let deps = []

export let mkdeps = ["muon", "pkgconf", "wayland-dev"]

export let sources = [
  p"https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/VERSION/downloads/wayland-protocols-VERSION.tar.xz",
]

export let checksums = [
  "4d2b2a9e3e099d017dc8107bf1c334d27bb87d9e4aff19a0c8d856d17cd41ef0",
]

proc patch_generated_header_install() [fs, error] {
  let build_file = p"meson.build"
  var text = fs.read_text(build_file)?

  let scanner_old = """dep_scanner = dependency('wayland-scanner',
    version: get_option('tests') ? '>=1.23.0' : '>=1.20.0',
    native: true,
    fallback: 'wayland'
)
prog_scanner = find_program(dep_scanner.get_variable(pkgconfig: 'wayland_scanner', internal: 'wayland_scanner'))
"""

  if scanner_old in text {
    fs.write(build_file, text.replace(scanner_old, ""))?
  }

  text = fs.read_text(build_file)?

  let old = """include_dirs = []
if dep_scanner.version().version_compare('>=1.22.90')
	subdir('include/wayland-protocols')
	include_dirs = ['include']
endif"""

  if old in text {
    fs.write(build_file, text.replace(old, "include_dirs = []"))?
  }
}

proc prune_x_compat_protocols(root: Path) [fs, error] {
  fs.remove(fp"${root}/usr/share/wayland-protocols/staging/xwayland-shell/xwayland-shell-v1.xml", missing_ok: true)?
  fs.remove(fp"${root}/usr/share/wayland-protocols/staging/xwayland-shell", missing_ok: true)?

  fs.remove(
    fp"${root}/usr/share/wayland-protocols/unstable/xwayland-keyboard-grab/xwayland-keyboard-grab-unstable-v1.xml",
    missing_ok: true,
  )?

  fs.remove(fp"${root}/usr/share/wayland-protocols/unstable/xwayland-keyboard-grab", missing_ok: true)?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let pc = pm_env.pkg_config_context()?
  patch_generated_header_install()?

  env {
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" pm_env.meson_prefix_arg() "-Dtests=false" "build" ?

    env {
      DESTDIR = dest
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?

  prune_x_compat_protocols(dest)?
}
