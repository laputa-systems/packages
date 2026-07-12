use pm.env as pm_env
use pm.make as make

export let name = "fontconfig"

export let ver = "2.17.1"

export let rel = "8"

export let deps = ["musl", "freetype", "expat"]

export let mkdeps_host = ["llvm-toolchain", "muon", "samurai", "pkgconf", "freetype", "expat"]

export let upstream_sources = [
  {
    source: p"https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/VERSION/fontconfig-VERSION.tar.xz",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "9f5cae93f4fffc1fbc05ae99cdfc708cd60dfd6612ffc0512827025c026fa541",
      },
    ],
  },
  {
    source: p"files/generated/fccase.h => generated",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "299726ec60bc7a06ce3e523c75aef6745cb94cec4450e8ad53817427a3f7c84b",
      },
    ],
  },
  {
    source: p"files/generated/fclang.h => generated",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "3286b76659e4b23c34d2d133a8356253ce8eafb1f37475f7aff560ebad6d5863",
      },
    ],
  },
  {
    source: p"files/generated/35-lang-normalize.conf => generated",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "b89ed7c4a85f411112db8e0377a509fc68e3a1532d0b668970b766e140187c60",
      },
    ],
  },
]

type Declaration = {name: Str, define_name: Str}

let conf_links = [
  "10-scale-bitmap-fonts.conf",
  "10-yes-antialias.conf",
  "11-lcdfilter-default.conf",
  "20-unhint-small-vera.conf",
  "30-metric-aliases.conf",
  "40-nonlatin.conf",
  "45-generic.conf",
  "45-latin.conf",
  "48-spacing.conf",
  "49-sansserif.conf",
  "50-user.conf",
  "51-local.conf",
  "60-generic.conf",
  "60-latin.conf",
  "65-fonts-persian.conf",
  "65-nonlatin.conf",
  "69-unifont.conf",
  "80-delicious.conf",
  "90-synthetic.conf",
  "10-hinting-slight.conf",
  "10-sub-pixel-none.conf",
  "70-no-bitmaps-except-emoji.conf",
]

export let filetree = [
  {
    path: p"etc/fonts/conf.d/10-hinting-slight.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/10-scale-bitmap-fonts.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/10-sub-pixel-none.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/10-yes-antialias.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/11-lcdfilter-default.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/20-unhint-small-vera.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/30-metric-aliases.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/40-nonlatin.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/45-generic.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/45-latin.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/48-spacing.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/49-sansserif.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/50-user.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/51-local.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/60-generic.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/60-latin.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/65-fonts-persian.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/65-nonlatin.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/69-unifont.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/70-no-bitmaps-except-emoji.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/80-delicious.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/90-synthetic.conf",
    kind: "symlink",
  },
  {
    path: p"etc/fonts/conf.d/README",
    kind: "file",
  },
  {
    path: p"etc/fonts/fonts.conf",
    kind: "file",
  },
  {
    path: p"usr/bin/fc-cache",
    kind: "binary",
  },
  {
    path: p"usr/bin/fc-match",
    kind: "binary",
  },
  {
    path: p"usr/include/fontconfig/fcfreetype.h",
    kind: "file",
  },
  {
    path: p"usr/include/fontconfig/fcprivate.h",
    kind: "file",
  },
  {
    path: p"usr/include/fontconfig/fontconfig.h",
    kind: "file",
  },
  {
    path: p"usr/lib/libfontconfig.so",
    kind: "symlink",
  },
  {
    path: p"usr/lib/libfontconfig.so.1",
    kind: "symlink",
  },
  {
    path: p"usr/lib/libfontconfig.so.1.16.0",
    kind: "binary",
  },
  {
    path: p"usr/lib/pkgconfig/fontconfig.pc",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/05-reset-dirs-sample.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/09-autohint-if-no-hinting.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/10-autohint.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/10-hinting-full.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/10-hinting-medium.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/10-hinting-none.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/10-hinting-slight.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/10-no-antialias.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/10-scale-bitmap-fonts.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/10-sub-pixel-bgr.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/10-sub-pixel-none.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/10-sub-pixel-rgb.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/10-sub-pixel-vbgr.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/10-sub-pixel-vrgb.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/10-unhinted.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/10-yes-antialias.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/11-lcdfilter-default.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/11-lcdfilter-legacy.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/11-lcdfilter-light.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/11-lcdfilter-none.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/20-unhint-small-vera.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/25-unhint-nonlatin.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/30-metric-aliases.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/35-lang-normalize.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/40-nonlatin.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/45-generic.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/45-latin.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/48-guessfamily.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/48-spacing.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/49-sansserif.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/50-user.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/51-local.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/60-generic.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/60-latin.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/65-fonts-persian.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/65-khmer.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/65-nonlatin.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/69-unifont.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/70-no-bitmaps-and-emoji.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/70-no-bitmaps-except-emoji.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/70-no-bitmaps.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/70-yes-bitmaps.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/80-delicious.conf",
    kind: "file",
  },
  {
    path: p"usr/share/fontconfig/conf.avail/90-synthetic.conf",
    kind: "file",
  },
  {
    path: p"usr/share/xml/fontconfig/fonts.dtd",
    kind: "file",
  },
]

pure c_string(text: Str) -> Str {
  text.replace("\\", "\\\\").replace("\"", "\\\"")
}

pure c_ident(raw: Str) -> Str {
  raw.replace("-", "_").replace(".", "_")
}

proc extract_function_names(path_value: Path) [fs, error] -> Result[List[Str]] {
  let re = regex.compile("^(Fc[^ ]*)[ A-Za-z0-9_]*\\(.*")?
  var names = []

  for line in path_value.read_text()?.split("\n") {
    let captures = re.captures(line.trim())

    if captures.len() > 1 {
      let name_value = captures[1]

      if name_value != "FcCacheDir" and name_value != "FcCacheSubdir" {
        names = names.push(name_value)
      }
    }
  }

  names
}

proc source_definitions() [fs, error] -> Result[Map[Str]] {
  var definitions: Map[Str] = {}

  for entry in fs.ls(p"src")? |> where .kind == "file" and .ext == "c" {
    let define_name = f"__${entry.name.replace(".c", "")}__"

    for name_value in extract_function_names(entry.path)? {
      definitions[name_value] = define_name
    }
  }

  definitions
}

proc alias_declarations(headers: List[Path]) [fs, error] -> Result[List[Declaration]] {
  let definitions = source_definitions()?
  var declarations = []
  var seen: Map[Bool] = {}

  for header in headers {
    for name_value in extract_function_names(header)? {
      if ! seen.get(name_value, false) {
        let define_name = definitions.get(name_value)?
        declarations = declarations.push({name: name_value, define_name})
        seen[name_value] = true
      }
    }
  }

  declarations
}

proc write_alias_headers(head: Path, tail: Path, headers: List[Path]) [fs, error] {
  let _ = headers
  fs.write(head, "")?
  fs.write(tail, "")?
}

proc write_fcobjshash() [fs, error] {
  fs.write(
    p"src/fcobjshash.h",
    """#include <string.h>

struct FcObjectTypeInfo {
	const char *name;
	int id;
};

static const struct FcObjectTypeInfo fc_object_type_info[] = {
#define FC_OBJECT(NAME, Type, Cmp) { FC_##NAME, FC_##NAME##_OBJECT },
#include "fcobjs.h"
#undef FC_OBJECT
};

static unsigned int
FcObjectTypeHash (register const char *str, register FC_GPERF_SIZE_T len)
{
	(void)str;
	return (unsigned int)len;
}

static const struct FcObjectTypeInfo *
FcObjectTypeLookup (register const char *str, register FC_GPERF_SIZE_T len)
{
	for (unsigned int i = 0; i < sizeof(fc_object_type_info) / sizeof(fc_object_type_info[0]); i++) {
		if (strlen(fc_object_type_info[i].name) == len && memcmp(fc_object_type_info[i].name, str, len) == 0)
			return &fc_object_type_info[i];
	}
	return 0;
}
""",
  )?
}

proc patch_generated_build_inputs() [fs, error] {
  fs.remove(p"fc-case/fccase.h", missing_ok: true)?
  fs.remove(p"fc-lang/fclang.h", missing_ok: true)?
  fs.remove(p"conf.d/35-lang-normalize.conf", missing_ok: true)?
  fs.install(p"generated/fccase.h", p"fc-case/fccase.h", 0o644, overwrite: true)?
  fs.install(p"generated/fclang.h", p"fc-lang/fclang.h", 0o644, overwrite: true)?
  fs.install(p"generated/35-lang-normalize.conf", p"conf.d/35-lang-normalize.conf", 0o644, overwrite: true)?

  write_alias_headers(
    p"fcalias.h",
    p"fcaliastail.h",
    [p"fontconfig/fontconfig.h.in", p"src/fcdeprecate.h", p"fontconfig/fcprivate.h"],
  )?

  write_alias_headers(p"fcftalias.h", p"fcftaliastail.h", [p"fontconfig/fcfreetype.h"])?
  write_fcobjshash()?
  let meson = p"meson.build"
  var text = meson.read_text()?

  text = text.replace(
    """    'rust_std=2021',
""",
    "",
  )

  text = text.replace(
    "math_dep = cc.find_library('m', required: false)",
    "math_dep = declare_dependency(link_args: ['-lm'])",
  )

  text = text.replace(
    """foreach check : check_sizeofs
  type = check[0]
  opts = check.length() > 1 ? check[1] : {}

  conf_name = opts.get('conf-name', 'SIZEOF_@0@'.format(type.to_upper()))

  conf.set(conf_name, cc.sizeof(type))
endforeach

foreach check : check_alignofs
  type = check[0]
  opts = check.length() > 1 ? check[1] : {}

  conf_name = opts.get('conf-name', 'ALIGNOF_@0@'.format(type.to_upper()))

  conf.set(conf_name, cc.alignment(type))
endforeach
""",
    """foreach check : check_sizeofs
  type = check[0]
  opts = check.length() > 1 ? check[1] : {}
  conf_name = opts.get('conf-name', 'SIZEOF_@0@'.format(type.to_upper()))
  conf.set(conf_name, type == 'void *' ? 8 : cc.sizeof(type))
endforeach

foreach check : check_alignofs
  type = check[0]
  opts = check.length() > 1 ? check[1] : {}
  conf_name = opts.get('conf-name', 'ALIGNOF_@0@'.format(type.to_upper()))
  conf.set(conf_name, (type == 'void *' or type == 'double') ? 8 : cc.alignment(type))
endforeach
""",
  )

  text = text.replace("python3 = import('python').find_installation()", "python3 = 'vendored-generated'")
  text = text.replace("gperf = find_program('gperf')", "gperf = 'vendored-gperf'")

  text = text.replace(
    """gperf = find_program('gperf', required: false)
gperf_len_type = ''

if gperf.found() and get_option('wrap_mode') != 'forcefallback'
  gperf_test_format = '''
#include <string.h>
const char * in_word_set(const char *, @0@);
const char * s = "";
int main(void) { return in_word_set(s, strlen(s)) != 0; }
'''
  gperf_snippet = run_command(gperf, '-L', 'ANSI-C', files('meson-cc-tests/gperf.txt'),
                              check: true).stdout()
  foreach type: ['size_t', 'unsigned int']
    if cc.compiles(gperf_test_format.format(type, gperf_snippet))
      gperf_len_type = type
      break
    endif
  endforeach
  if gperf_len_type == ''
    error('unable to determine gperf len type')
  endif
else
  gperf = find_program('gperf')
  gperf_len_type = 'size_t'
endif
""",
    """gperf_len_type = 'size_t'
""",
  )

  text = text.replace(
    """alias_headers = custom_target('alias_headers',
                              output: ['fcalias.h', 'fcaliastail.h'],
                              input: alias_input_headers,
                              command: [python3, makealias, join_paths(meson.current_source_dir(), 'src'), '@OUTPUT@', '@INPUT@'],
                             )

ft_alias_headers = custom_target('ft_alias_headers',
                                 output: ['fcftalias.h', 'fcftaliastail.h'],
                                 input: ['fontconfig/fcfreetype.h'],
                                 command: [python3, makealias, join_paths(meson.current_source_dir(), 'src'), '@OUTPUT@', '@INPUT@']
                                )
""",
    """alias_headers = files('fcalias.h', 'fcaliastail.h')
ft_alias_headers = files('fcftalias.h', 'fcftaliastail.h')
""",
  )

  fs.write(meson, text)?
  let src_meson = p"src/meson.build"

  fs.write(
    src_meson,
    src_meson.read_text()?.replace(
  """fcobjshash_h = cc.preprocess('fcobjshash.gperf.h', include_directories: incbase)
fcobjshash_gperf = custom_target(
  input: fcobjshash_h,
  output: 'fcobjshash.gperf',
  command: ['cutout.py', '@INPUT@', '@OUTPUT@'],
  build_by_default: true,
)

fcobjshash_h = custom_target('fcobjshash.h',
  input: fcobjshash_gperf,
  output: 'fcobjshash.h',
  command: [gperf, '--pic', '-m', '100', '@INPUT@', '--output-file', '@OUTPUT@']
)
""",
  """fcobjshash_h = files('fcobjshash.h')
""",
),
  )?

  let fc_case_meson = p"fc-case/meson.build"

  fs.write(
    fc_case_meson,
    fc_case_meson.read_text()?.replace(
  """fccase_h = custom_target('fccase.h',
  output: 'fccase.h',
  input: ['CaseFolding.txt', 'fccase.tmpl.h'],
  command: [find_program('fc-case.py'), '@INPUT0@', '--template', '@INPUT1@', '--output', '@OUTPUT@'])
""",
  """fccase_h = files('fccase.h')
""",
),
  )?

  let fc_lang_meson = p"fc-lang/meson.build"

  fs.write(
    fc_lang_meson,
    fc_lang_meson.read_text()?.replace(
  """fclang_h = custom_target('fclang.h',
  output: ['fclang.h'],
  input: orth_files,
  command: [find_program('fc-lang.py'), orth_files, '--template', files('fclang.tmpl.h')[0], '--output', '@OUTPUT@', '--directory', meson.current_source_dir()],
  build_by_default: true,
)
""",
  """fclang_h = files('fclang.h')
""",
),
  )?

  let conf_meson = p"conf.d/meson.build"
  var conf_text = conf_meson.read_text()?

  conf_text = conf_text.replace(
    """custom_target('35-lang-normalize.conf',
  output: '35-lang-normalize.conf',
  command: [find_program('write-35-lang-normalize-conf.py'), ','.join(orths), '@OUTPUT@'],
  install_dir: fc_templatedir,
  install: true,
  install_tag: 'runtime')
""",
    """install_data('35-lang-normalize.conf',
             install_dir: fc_templatedir,
             install_tag: 'runtime')
""",
  )

  conf_text = conf_text.replace(
    """meson.add_install_script('link_confs.py', fc_templatedir,
                         fc_configdir,
                         conf_links,
                         install_tag: 'runtime')
""",
    "",
  )

  fs.write(conf_meson, conf_text)?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${make.jobs()?}"
  let pc = pm_env.pkg_config_context()?
  patch_generated_build_inputs()?

  env {
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() pm_env.meson_sysconfdir_arg() pm_env.meson_localstatedir_arg() "-Ddefault_library=shared" "-Ddoc=disabled" "-Dtests=disabled" "-Dnls=disabled" "-Diconv=disabled" "-Dxml-backend=expat" "-Dfontations=disabled" "-Dcache-build=disabled" "-Dtools=enabled" "build" ?
    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?

  for bin in ["fc-cat", "fc-conflist", "fc-list", "fc-pattern", "fc-query", "fc-scan", "fc-validate"] {
    fs.remove(fp"${dest}/usr/bin/${bin}", missing_ok: true)?
  }

  for conf in conf_links {
    fs.symlink(fp"../../share/fontconfig/conf.avail/${conf}", fp"${dest}/etc/fonts/conf.d/${conf}")?
  }

  fs.remove(fp"${dest}/usr/share/man", missing_ok: true)?
  fs.remove(fp"${dest}/usr/share/gettext", missing_ok: true)?
}
