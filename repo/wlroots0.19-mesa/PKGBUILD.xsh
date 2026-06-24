use pm.meson as pm_meson
use pm.util as pm_util

export let name: Str = "wlroots0.19-mesa"

export let ver: Str = "0.19.3"

export let rel: Str = "12"

export let deps: List[Str] = [
  "musl",
  "wayland-libs-server",
  "wayland-libs-client",
  "libdrm",
  "libxkbcommon",
  "pixman",
  "mesa-minimal",
  "libudev-zero",
  "libseat",
  "libinput",
  "libdisplay-info",
]

export let replaces: List[Str] = ["wlroots0.19-minimal"]

export let mkdeps: List[Str] = [
  "llvm-toolchain",
  "linux",
  "muon",
  "samurai",
  "pkgconf",
  "wayland-dev",
  "wayland-protocols",
  "libdrm",
  "libxkbcommon",
  "pixman-dev",
  "mesa-minimal",
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

pure c_multiline_string(text: Str) -> Str {
  c_string(text).replace(
    "\n",
    """\\n"
\"""",
  )
}

proc write_shader_header(src: Path, dest: Path, symbol: Str) [fs, error] {
  fs.write(
    dest,
    f"""static const char ${symbol}[] =
"${c_multiline_string(src.read_text()?)}";
""",
  )?
}

proc write_shader_headers() [fs, error] {
  write_shader_header(p"render/gles2/shaders/common.vert", p"render/gles2/shaders/common_vert_src.h", "common_vert_src")?
  write_shader_header(p"render/gles2/shaders/quad.frag", p"render/gles2/shaders/quad_frag_src.h", "quad_frag_src")?

  write_shader_header(
    p"render/gles2/shaders/tex_rgba.frag",
    p"render/gles2/shaders/tex_rgba_frag_src.h",
    "tex_rgba_frag_src",
  )?

  write_shader_header(
    p"render/gles2/shaders/tex_rgbx.frag",
    p"render/gles2/shaders/tex_rgbx_frag_src.h",
    "tex_rgbx_frag_src",
  )?

  write_shader_header(
    p"render/gles2/shaders/tex_external.frag",
    p"render/gles2/shaders/tex_external_frag_src.h",
    "tex_external_frag_src",
  )?
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
  write_shader_headers()?
  let meson = p"meson.build"

  fs.write(meson, 
    meson.read_text()?.replace(
      """math = cc.find_library('m')
rt = cc.find_library('rt')""",
      """# musl packages libm as a libc symlink and provides realtime interfaces in libc.
math = declare_dependency(link_args: ['-lm'])
rt = declare_dependency()""",
    ),
  )?

  let drm_meson = p"backend/drm/meson.build"

  fs.write(drm_meson, 
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

  fs.write(protocol_meson, 
    protocol_meson.read_text()?.replace(
      """	'xwayland-shell-v1': wl_protocol_dir / 'staging/xwayland-shell/xwayland-shell-v1.xml',
""",
      "",
    ),
  )?

  let renderer = p"render/gles2/renderer.c"

  fs.write(renderer, 
    renderer.read_text()?.replace(
      """#include "common_vert_src.h"
#include "quad_frag_src.h"
#include "tex_rgba_frag_src.h"
#include "tex_rgbx_frag_src.h"
#include "tex_external_frag_src.h"
""",
      """#include "shaders/common_vert_src.h"
#include "shaders/quad_frag_src.h"
#include "shaders/tex_rgba_frag_src.h"
#include "shaders/tex_rgbx_frag_src.h"
#include "shaders/tex_external_frag_src.h"
""",
    ),
  )?

  let shader_meson = p"render/gles2/shaders/meson.build"

  fs.write(shader_meson, 
    shader_meson.read_text()?.replace(
      """embed = find_program('./embed.sh', native: true)

""",
      "",
    ).replace(
      """	wlr_files += custom_target(
		output,
		command: [embed, var],
		input: name,
		output: output,
		feed: true,
		capture: true,
	)
""",
      """	wlr_files += files(output)
""",
    ),
  )?
}

proc prune_xwayland_headers(root: Path) [fs, error] {
  fs.remove(fp"${root}/usr/include/wlroots-0.19/wlr/xwayland.h", missing_ok: true)?
  fs.remove(fp"${root}/usr/include/wlroots-0.19/wlr/xwayland/server.h", missing_ok: true)?
  fs.remove(fp"${root}/usr/include/wlroots-0.19/wlr/xwayland/shell.h", missing_ok: true)?
  fs.remove(fp"${root}/usr/include/wlroots-0.19/wlr/xwayland/xwayland.h", missing_ok: true)?
  fs.remove(fp"${root}/usr/include/wlroots-0.19/wlr/xwayland", missing_ok: true)?
}

proc replace_dep(input_deps: List[Str], old_dep: Str, new_dep: Str) [error] -> List[Str] {
  var next: List[Str] = []

  for dep in input_deps {
    if dep == old_dep {
      if ! next.contains(new_dep) {
        next = next.push(new_dep)
      }
    } else if ! next.contains(dep) {
      next = next.push(dep)
    }
  }

  next
}

proc rewrite_installed_dependency(root: Path, old_dep: Str, new_dep: Str) [fs, error] {
  let packages = fp"${root}/var/lib/xsh-pm/packages"

  if ! fs.exists(packages)? {
    return
  }

  for entry in fs.ls(packages)? |> where .kind == "dir" {
    let metadata_path = fp"${entry.path}/metadata.json"

    if fs.exists(metadata_path)? {
      let metadata: Record = json.read(metadata_path)?
      let metadata_deps: List[Str] = metadata.get("deps")?
      let metadata_mkdeps: List[Str] = metadata.get("mkdeps")?
      let next_deps = replace_dep(metadata_deps, old_dep, new_dep)
      let next_mkdeps = replace_dep(metadata_mkdeps, old_dep, new_dep)

      if next_deps != metadata_deps or next_mkdeps != metadata_mkdeps {
        let metadata_name: Str = metadata.get("name")?
        let metadata_ver: Str = metadata.get("ver")?
        let metadata_rel: Str = metadata.get("rel")?
        let nostrip: Bool = metadata.get("nostrip")?
        let dir: Str = metadata.get("dir")?

        json.write(
          metadata_path,
          {
            name: metadata_name,
            ver: metadata_ver,
            rel: metadata_rel,
            deps: next_deps,
            mkdeps: next_mkdeps,
            nostrip,
            dir,
          },
        )?
      }
    }
  }
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
    run $muon "setup" "-Dprefix=/usr" "-Dlibdir=lib" "-Ddefault_library=shared" "-Dauto_features=disabled" "-Dwerror=false" "-Dbackends=drm,libinput" "-Drenderers=gles2" "-Dallocators=gbm" "-Dsession=enabled" "-Dxwayland=disabled" "-Dcolor-management=disabled" "-Dlibliftoff=disabled" "-Dxcb-errors=disabled" "-Dexamples=false" "build" ?

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
      fs.write(ninja, ninja_text)?
    }

    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest.display()
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?

  prune_xwayland_headers(dest)?
}

export proc pre_install(root: Path) [fs, error] {
  prune_xwayland_headers(root)?
  fs.remove(fp"${root}/var/lib/xsh-pm/packages/wlroots0.19-minimal", missing_ok: true)?
}

export proc post_install(root: Path) [fs, error] {
  rewrite_installed_dependency(root, "wlroots0.19-minimal", "wlroots0.19-mesa")?
}
