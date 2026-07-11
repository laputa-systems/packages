use pm.env as pm_env

export let name = "wayland-protocols"

export let ver = "1.45"

export let rel = "9"

export let deps = []

export let mkdeps_host = ["muon", "pkgconf", "wayland-dev"]

export let sources = [
  p"https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/VERSION/downloads/wayland-protocols-VERSION.tar.xz",
]

export let checksums = ["4d2b2a9e3e099d017dc8107bf1c334d27bb87d9e4aff19a0c8d856d17cd41ef0"]

export let filetree = [
  {path: p"usr/share/pkgconfig/wayland-protocols.pc", kind: "file"},
  {path: p"usr/share/wayland-protocols/stable/linux-dmabuf/linux-dmabuf-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/stable/presentation-time/presentation-time.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/stable/tablet/tablet-v2.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/stable/viewporter/viewporter.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/alpha-modifier/alpha-modifier-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/color-management/color-management-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/color-representation/color-representation-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/commit-timing/commit-timing-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/content-type/content-type-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/cursor-shape/cursor-shape-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/drm-lease/drm-lease-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/ext-background-effect/ext-background-effect-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/ext-data-control/ext-data-control-v1.xml", kind: "file"},
  {
    path: p"usr/share/wayland-protocols/staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml",
    kind: "file",
  },
  {path: p"usr/share/wayland-protocols/staging/ext-idle-notify/ext-idle-notify-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/ext-image-capture-source/ext-image-capture-source-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/ext-image-copy-capture/ext-image-copy-capture-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/ext-session-lock/ext-session-lock-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/ext-transient-seat/ext-transient-seat-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/ext-workspace/ext-workspace-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/fifo/fifo-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/fractional-scale/fractional-scale-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/linux-drm-syncobj/linux-drm-syncobj-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/pointer-warp/pointer-warp-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/security-context/security-context-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/single-pixel-buffer/single-pixel-buffer-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/tearing-control/tearing-control-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/xdg-activation/xdg-activation-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/xdg-dialog/xdg-dialog-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/xdg-system-bell/xdg-system-bell-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/xdg-toplevel-drag/xdg-toplevel-drag-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/xdg-toplevel-icon/xdg-toplevel-icon-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/staging/xdg-toplevel-tag/xdg-toplevel-tag-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/fullscreen-shell/fullscreen-shell-unstable-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/idle-inhibit/idle-inhibit-unstable-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/input-method/input-method-unstable-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/input-timestamps/input-timestamps-unstable-v1.xml", kind: "file"},
  {
    path: p"usr/share/wayland-protocols/unstable/keyboard-shortcuts-inhibit/keyboard-shortcuts-inhibit-unstable-v1.xml",
    kind: "file",
  },
  {path: p"usr/share/wayland-protocols/unstable/linux-dmabuf/linux-dmabuf-unstable-v1.xml", kind: "file"},
  {
    path: p"usr/share/wayland-protocols/unstable/linux-explicit-synchronization/linux-explicit-synchronization-unstable-v1.xml",
    kind: "file",
  },
  {path: p"usr/share/wayland-protocols/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/pointer-gestures/pointer-gestures-unstable-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/primary-selection/primary-selection-unstable-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/relative-pointer/relative-pointer-unstable-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/tablet/tablet-unstable-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/tablet/tablet-unstable-v2.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/text-input/text-input-unstable-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/text-input/text-input-unstable-v3.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/xdg-foreign/xdg-foreign-unstable-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/xdg-foreign/xdg-foreign-unstable-v2.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/xdg-output/xdg-output-unstable-v1.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/xdg-shell/xdg-shell-unstable-v5.xml", kind: "file"},
  {path: p"usr/share/wayland-protocols/unstable/xdg-shell/xdg-shell-unstable-v6.xml", kind: "file"},
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
