use pm.env as pm_env
use pm.util as pm_util

export let name = "wlroots0.19-mesa"

export let ver = "0.19.3"

export let rel = "18"

export let deps = [
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

export let mkdeps_host = [
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

export let mkdeps_target = ["wayland-dev", "wayland-protocols", "pixman-dev"]

export let upstream_sources = [
  {
    source: p"https://gitlab.freedesktop.org/wlroots/wlroots/-/archive/VERSION/wlroots-VERSION.tar.gz",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "a6ff89b64ea15e424d1b0db4a22145fccf5ec2ff2e7b8af0fa35e2ac8975986f",
      },
    ],
  },
]

type PnpRecord = {id: Str, vendor: Str}

export let filetree = [
  {
    path: p"usr/include/wlroots-0.19/wlr/backend.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/backend/drm.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/backend/headless.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/backend/interface.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/backend/libinput.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/backend/multi.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/backend/session.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/backend/wayland.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/config.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/interfaces/wlr_buffer.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/interfaces/wlr_ext_image_capture_source_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/interfaces/wlr_keyboard.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/interfaces/wlr_output.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/interfaces/wlr_pointer.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/interfaces/wlr_switch.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/interfaces/wlr_tablet_pad.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/interfaces/wlr_tablet_tool.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/interfaces/wlr_touch.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/render/allocator.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/render/color.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/render/dmabuf.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/render/drm_format_set.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/render/drm_syncobj.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/render/egl.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/render/gles2.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/render/interface.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/render/pass.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/render/pixman.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/render/swapchain.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/render/wlr_renderer.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/render/wlr_texture.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_alpha_modifier_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_buffer.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_color_management_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_compositor.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_content_type_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_cursor.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_cursor_shape_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_damage_ring.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_data_control_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_data_device.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_drm.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_drm_lease_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_export_dmabuf_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_ext_data_control_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_ext_foreign_toplevel_list_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_ext_image_capture_source_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_ext_image_copy_capture_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_foreign_toplevel_management_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_fractional_scale_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_gamma_control_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_idle_inhibit_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_idle_notify_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_input_device.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_input_method_v2.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_keyboard.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_keyboard_group.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_keyboard_shortcuts_inhibit_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_layer_shell_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_linux_dmabuf_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_linux_drm_syncobj_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_output.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_output_layer.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_output_layout.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_output_management_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_output_power_management_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_output_swapchain_manager.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_pointer.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_pointer_constraints_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_pointer_gestures_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_presentation_time.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_primary_selection.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_primary_selection_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_relative_pointer_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_scene.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_screencopy_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_seat.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_security_context_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_server_decoration.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_session_lock_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_shm.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_single_pixel_buffer_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_subcompositor.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_switch.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_tablet_pad.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_tablet_tool.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_tablet_v2.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_tearing_control_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_text_input_v3.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_touch.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_transient_seat_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_viewporter.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_virtual_keyboard_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_virtual_pointer_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_xcursor_manager.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_xdg_activation_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_xdg_decoration_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_xdg_dialog_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_xdg_foreign_registry.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_xdg_foreign_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_xdg_foreign_v2.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_xdg_output_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_xdg_shell.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_xdg_system_bell_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/types/wlr_xdg_toplevel_icon_v1.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/util/addon.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/util/box.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/util/edges.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/util/log.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/util/region.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/util/transform.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/version.h",
    kind: "file",
  },
  {
    path: p"usr/include/wlroots-0.19/wlr/xcursor.h",
    kind: "file",
  },
  {
    path: p"usr/lib/libwlroots-0.19.so",
    kind: "binary",
  },
  {
    path: p"usr/lib/pkgconfig/wlroots-0.19.pc",
    kind: "file",
  },
]

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
  var cases = []

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

  fs.write(
    meson,
    meson.read_text()?.replace(
  """math = cc.find_library('m')
rt = cc.find_library('rt')""",
  """# musl packages libm as a libc symlink and provides realtime interfaces in libc.
math = declare_dependency(link_args: ['-lm'])
rt = declare_dependency()""",
),
  )?

  let drm_meson = p"backend/drm/meson.build"

  fs.write(
    drm_meson,
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

  fs.write(
    protocol_meson,
    protocol_meson.read_text()?.replace(
  """	'xwayland-shell-v1': wl_protocol_dir / 'staging/xwayland-shell/xwayland-shell-v1.xml',
""",
  "",
),
  )?

  let renderer = p"render/gles2/renderer.c"

  fs.write(
    renderer,
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

  fs.write(
    shader_meson,
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

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${cpu.count()}"
  let pc = pm_env.pkg_config_context()?
  let build_root = env.get("XSH_PM_BUILD_ROOT") ?? ""
  let native_scanner = pm_util.build_arch()? != pm_util.target_arch()? and build_root != ""

  let native_tools_ld = if native_scanner {
    f"${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib:${pc.ld_library_path}"
  } else {
    pc.ld_library_path
  }

  let root = env.get("LAPUTA_ROOT") ?? "/"
  patch_build(root)?

  env {
    CFLAGS = "-D__user="
    LD_LIBRARY_PATH = native_tools_ld
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() "-Ddefault_library=shared" "-Dauto_features=disabled" "-Dwerror=false" "-Dbackends=drm,libinput" "-Drenderers=gles2" "-Dallocators=gbm" "-Dsession=enabled" "-Dxwayland=disabled" "-Dcolor-management=disabled" "-Dlibliftoff=disabled" "-Dxcb-errors=disabled" "-Dexamples=false" "build" ?

    if native_scanner {
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

  prune_xwayland_headers(dest)?
}
