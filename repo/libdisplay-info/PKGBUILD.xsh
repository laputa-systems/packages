use pm.env as pm_env

export let name: Str = "libdisplay-info"

export let ver: Str = "0.3.0"

export let rel: Str = "5"

export let deps: List[Str] = ["musl", "hwdata"]

export let mkdeps: List[Str] = ["llvm-toolchain", "muon", "samurai", "pkgconf", "hwdata"]

export let sources: List[Path] = [
  p"https://gitlab.freedesktop.org/emersion/libdisplay-info/-/releases/VERSION/downloads/libdisplay-info-VERSION.tar.xz",
]

export let checksums: List[Str] = ["6ae77cd937f9cf7d1321d35c116062c4911e8447010a6a713ac4286f7a9d5987"]

type PnpRecord = {id: Str, name: Str}

pure c_string(text: Str) -> Str {
  text.replace("\\", "\\\\").replace("\"", "\\\"")
}

proc write_pnp_table(root: Str) [fs, error] {
  let pnp = fp"${root}/usr/share/hwdata/pnp.ids"
  var records: List[PnpRecord] = []

  for line in pnp.read_text()?.split("\n") {
    let trimmed = line.trim()

    if trimmed != "" {
      let words = trimmed.words()

      if words.len() >= 2 and words[0].count_chars() == 3 {
        let id = words[0]
        let display_name = trimmed.replace(id, "").trim()
        records = records.push({id, name: display_name})
      }
    }
  }

  records = records |> sort-by .id
  var cases = [f"    if (strcmp(key, \"${c_string(entry.id)}\") == 0) return \"${c_string(entry.name)}\";" for entry in records]
  let case_text = cases.join("\n")

  fs.write(
    p"pnp-id-table.c",
    f"""#include <string.h>

const char *
pnp_id_table(const char *key);

const char *
pnp_id_table(const char *key)
{{
${case_text}
    return NULL;
}}
""",
  )?
}

proc patch_generators(root: Str) [fs, error] {
  write_pnp_table(root)?
  let meson_path = p"meson.build"
  var text = meson_path.read_text()?

  text = text.replace(
    """gen_search_table = find_program('tool/gen-search-table.py')
pnp_id_table = custom_target(
	'pnp-id-table.c',
	command: [ gen_search_table, pnp_ids, '@OUTPUT@', 'pnp_id_table' ],
	output: 'pnp-id-table.c',
)
""",
    """pnp_id_table = files('pnp-id-table.c')
""",
  )

  text = text.replace(
    """
subdir('di-edid-decode')
subdir('test')
""",
    "\n",
  )

  text = text.replace("math = cc.find_library('m', required: false)", "math = declare_dependency(link_args: ['-lm'])")
  fs.write(meson_path, text)?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${cpu.count()}"
  let pc = pm_env.pkg_config_context()?
  let root = env.get("LAPUTA_ROOT") ?? "/"
  patch_generators(root)?

  env {
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() "-Ddefault_library=shared" "-Dtest=false" "build" ?
    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?
}
