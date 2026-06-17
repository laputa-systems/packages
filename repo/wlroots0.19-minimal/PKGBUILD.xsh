use pm.meson as pm_meson
use pm.util as pm_util

export let name: Str = "wlroots0.19-minimal"

export let ver: Str = "0.19.3"

export let rel: Str = "4"

export let deps: List[Str] = [
  "musl",
  "wayland-libs-server",
  "wayland-libs-client",
  "libdrm",
  "libxkbcommon",
  "pixman",
  "libudev-zero",
  "libseat",
  "libinput",
  "libdisplay-info",
]

export let mkdeps: List[Str] = [
  "llvm-toolchain",
  "linux",
  "muon",
  "pkgconf",
  "wayland-dev",
  "wayland-protocols",
  "libdrm",
  "libxkbcommon",
  "pixman-dev",
  "libudev-zero",
  "libseat",
  "libinput",
  "libdisplay-info",
]

export let target_build_deps: List[Str] = ["wayland-dev", "wayland-protocols", "pixman-dev"]

export let sources: List[Path] = [
  p"https://gitlab.freedesktop.org/wlroots/wlroots/-/archive/VERSION/wlroots-VERSION.tar.gz",
]

export let checksums: List[Str] = ["a6ff89b64ea15e424d1b0db4a22145fccf5ec2ff2e7b8af0fa35e2ac8975986f"]

type PnpRecord = {id: Str, vendor: Str}

pure c_string(text: Str) -> Str {
  text.replace("\\", "\\\\").replace("\"", "\\\"")
}

proc write_pnpids(root: Str) [fs, error] {
  let pnp = fp"${root}/usr/share/hwdata/pnp.ids"
  var records: List[PnpRecord] = []

  for line in pnp.read_text()?.split("\n") {
    let trimmed = line.trim()

    if trimmed != "" {
      let words = trimmed.words()

      if words.len() >= 2 and words[0].count_chars() == 3 {
        records = records.push({id: words[0], vendor: trimmed.replace(words[0], "").trim()})
      }
    }
  }

  records = records |> sort-by .id
  var cases: List[Str] = []

  for entry in records {
    let chars = entry.id.split("")

    if chars.len() == 3 {
      cases = cases.push(
        f"    case PNP_ID('${c_string(chars[0])}', '${c_string(chars[1])}', '${c_string(chars[2])}'): return \"${c_string(
          entry.vendor,
        )}\";",
      )
    }
  }

  fs.write(
    p"backend/drm/pnpids.c",
    f"""#include "backend/drm/util.h"

#define PNP_ID(a, b, c) ((a & 0x1f) << 10) | ((b & 0x1f) << 5) | (c & 0x1f)
const char *get_pnp_manufacturer(const char code[static 3]) {{
	switch (PNP_ID(code[0], code[1], code[2])) {{
${cases.join("\n")}
	}}
	return NULL;
}}
#undef PNP_ID
""",
  )?
}

proc patch_build(root: Str) [fs, error] {
  write_pnpids(root)?
  let meson = p"meson.build"

  meson.write_atomic(
    meson.read_text()?.replace(
      """math = cc.find_library('m')
rt = cc.find_library('rt')""",
      """# musl packages libm as a libc symlink and provides realtime interfaces in libc.
math = declare_dependency(link_args: ['-lm'])
rt = declare_dependency()""",
    ),
  )?

  let drm_meson = p"backend/drm/meson.build"

  drm_meson.write_atomic(
    drm_meson.read_text()?.replace(
      """pnpids_c = custom_target(
	'pnpids.c',
	output: 'pnpids.c',
	input: files(hwdata_dir / 'pnp.ids'),
	feed: true,
	capture: true,
	command: files('gen_pnpids.sh'),
)
""",
      """pnpids_c = files('pnpids.c')
""",
    ),
  )?

  let protocol_meson = p"protocol/meson.build"

  protocol_meson.write_atomic(
    protocol_meson.read_text()?.replace(
      """	'xwayland-shell-v1': wl_protocol_dir / 'staging/xwayland-shell/xwayland-shell-v1.xml',
""",
      "",
    ),
  )?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${cpu.count()}"
  let pc = pm_meson.pkg_config_env()?
  let build_root = env.get("XSH_PM_BUILD_ROOT") ?? ""
  let native_scanner = pm_util.build_arch()? != pm_util.target_arch()? and build_root != ""
  let root = env.get("LAPUTA_ROOT") ?? "/"
  patch_build(root)?

  env {
    CFLAGS = "-D__user="
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" "-Dprefix=/usr" "-Dlibdir=lib" "-Ddefault_library=shared" "-Dauto_features=disabled" "-Dwerror=false" "-Dbackends=drm,libinput" "-Dallocators=" "-Dsession=enabled" "-Dxwayland=disabled" "-Dcolor-management=disabled" "-Dlibliftoff=disabled" "-Dxcb-errors=disabled" "-Dexamples=false" "build" ?

    if native_scanner {
      let native_scanner_wrapper = fp"${fs.cwd()?}/build/wayland-scanner-native-wrapper"

      fs.write(
        native_scanner_wrapper,
        f"""#!/bin/sh
LD_LIBRARY_PATH="${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib"
export LD_LIBRARY_PATH
exec "${build_root}/usr/bin/wayland-scanner" "$@"
""",
      )?

      fs.chmod(native_scanner_wrapper, 0o755)?
      let ninja = p"build/build.ninja"
      let scanner_text = native_scanner_wrapper.display()
      var ninja_text = ninja.read_text()?
      ninja_text = ninja_text.replace("../../../../root/usr/bin/wayland-scanner", scanner_text)
      ninja_text = ninja_text.replace("../../../../build-root/usr/bin/wayland-scanner", scanner_text)
      ninja_text = ninja_text.replace(f"${build_root}/usr/bin/wayland-scanner", scanner_text)
      ninja.write_atomic(ninja_text)?
    }

    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest.display()
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?
}
