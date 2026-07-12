use pm.env as pm_env
use pm.make as make

export let name = "fcft-minimal"

export let ver = "3.3.3"

export let rel = "9"

export let deps = ["musl", "fontconfig", "freetype", "pixman"]

export let mkdeps_host = [
  "llvm-toolchain",
  "muon",
  "samurai",
  "pkgconf",
  "fontconfig",
  "freetype",
  "pixman-dev",
  "tllist",
]

export let mkdeps_target = ["pixman-dev", "tllist"]

export let upstream_sources = [
  {
    source: p"https://codeberg.org/dnkl/fcft/archive/VERSION.tar.gz",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "b0c0f4a599f43723736c8565b8b84337c4195077f07f1bb8bb3252bb13a2306a",
      },
    ],
  },
  {
    source: p"files/generated/emoji-data.h => generated",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "a06764871a5ea6f2a85f62656552011243069d3d6e1b4e4148aadbf5200aab86",
      },
    ],
  },
  {
    source: p"files/generated/unicode-compose-table.h => generated",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "b5e24cfe476b8e5b30c37614a7f5e4479e011659b3615d92e42713bb8005679d",
      },
    ],
  },
]

export let filetree = [
  {
    path: p"usr/include/fcft/fcft.h",
    kind: "file",
  },
  {
    path: p"usr/include/fcft/stride.h",
    kind: "file",
  },
  {
    path: p"usr/lib/libfcft.so",
    kind: "symlink",
  },
  {
    path: p"usr/lib/libfcft.so.4",
    kind: "symlink",
  },
  {
    path: p"usr/lib/libfcft.so.4.3.3",
    kind: "binary",
  },
  {
    path: p"usr/lib/pkgconfig/fcft.pc",
    kind: "file",
  },
]

proc write_version_header() [fs, error] {
  fs.write(
    p"version.h",
    f"""#define FCFT_VERSION "${ver}"
""",
  )?
}

proc patch_generated_inputs() [fs, error] {
  fs.install(p"generated/emoji-data.h", p"emoji-data.h", 0o644, overwrite: true)?
  fs.install(p"generated/unicode-compose-table.h", p"unicode-compose-table.h", 0o644, overwrite: true)?
  write_version_header()?
  let meson = p"meson.build"
  var text = meson.read_text()?
  text = text.replace("math = cc.find_library('m')", "math = declare_dependency(link_args: ['-lm'])")

  text = text.replace(
    """env = find_program('env', native: true)
generate_unicode_precompose_sh = files('generate-unicode-precompose.sh')
unicode_data = custom_target(
  'unicode-data',
  input: 'unicode/UnicodeData.txt',
  output: 'unicode-compose-table.h',
  command: [env, 'LC_ALL=C', generate_unicode_precompose_sh, '@INPUT@', '@OUTPUT@'])

python = find_program('python3')
generate_emoji_data_py = files('generate-emoji-data.py')
emoji_data = custom_target(
  'emoji-data',
  input: 'unicode/emoji-data.txt',
  output: 'emoji-data.h',
  command: [python, generate_emoji_data_py, '@INPUT@', '@OUTPUT@'])

generate_version_sh = files('generate-version.sh')
version = custom_target(
  'generate_version',
  build_always_stale: true,
  output: 'version.h',
  command: [env, 'LC_ALL=C', generate_version_sh, meson.project_version(), '@CURRENT_SOURCE_DIR@', '@OUTPUT@'])
""",
    """unicode_data = files('unicode-compose-table.h')
emoji_data = files('emoji-data.h')
version = files('version.h')
""",
  )

  fs.write(meson, text)?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${make.jobs()?}"
  let pc = pm_env.pkg_config_context()?
  patch_generated_inputs()?

  env {
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() "-Ddefault_library=shared" "-Dwerror=false" "-Ddocs=disabled" "-Dexamples=false" "-Dsvg-backend=none" "-Dgrapheme-shaping=disabled" "-Drun-shaping=disabled" "build" ?
    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?
}
