use pm.env as pm_env

export let name = "libxkbcommon"

export let ver = "1.11.0"

export let rel = "8"

export let deps = ["musl", "xkeyboard-config"]

export let mkdeps_host = ["llvm-toolchain", "muon", "samurai", "pkgconf", "xkeyboard-config"]

export let upstream_sources = [
  {
    source: p"https://github.com/xkbcommon/libxkbcommon/archive/xkbcommon-VERSION.tar.gz",
    kind: "auto",
    architectures: ["all"],
    checksums: [{arch: "all", sha256: "78a6b14f16e9a55025978c252e53ce9e16a02bfdb929550b9a0db5af87db7e02"}],
  },
  {
    source: p"files/parser.c => generated",
    kind: "auto",
    architectures: ["all"],
    checksums: [{arch: "all", sha256: "e237a6b6396515462e50c56041681c1b1ce83f8582e8ab661a48d91cdaf97a8e"}],
  },
  {
    source: p"files/parser.h => generated",
    kind: "auto",
    architectures: ["all"],
    checksums: [{arch: "all", sha256: "5abcf6696e29a393960b9d842a719b025fcaea2c8c41b2976b5fa5f28e763b96"}],
  },
]

export let filetree = [
  {path: p"usr/include/xkbcommon/xkbcommon-compat.h", kind: "file"},
  {path: p"usr/include/xkbcommon/xkbcommon-compose.h", kind: "file"},
  {path: p"usr/include/xkbcommon/xkbcommon-keysyms.h", kind: "file"},
  {path: p"usr/include/xkbcommon/xkbcommon-names.h", kind: "file"},
  {path: p"usr/include/xkbcommon/xkbcommon.h", kind: "file"},
  {path: p"usr/lib/libxkbcommon.so", kind: "symlink"},
  {path: p"usr/lib/libxkbcommon.so.0", kind: "symlink"},
  {path: p"usr/lib/libxkbcommon.so.0.11.0", kind: "binary"},
  {path: p"usr/lib/pkgconfig/xkbcommon.pc", kind: "file"},
]

proc patch_vendored_parser() [fs, error] {
  fs.install(p"generated/parser.c", p"src/xkbcomp/parser.c", 0o644, parents: true, overwrite: true)?
  fs.install(p"generated/parser.h", p"src/xkbcomp/parser.h", 0o644, parents: true, overwrite: true)?
  let meson = p"meson.build"
  var text = meson.read_text()?

  text = text.replace(
    """# libxkbcommon.
bison = find_program('bison', 'win_bison', required: true, version: '>= 3.6')
yacc = bison
yacc_gen = generator(
    bison,
    output: ['@BASENAME@.c', '@BASENAME@.h'],
    arguments: ['--defines=@OUTPUT1@', '-o', '@OUTPUT0@', '-p', '_xkbcommon_', '@INPUT@'],
)
""",
    """# libxkbcommon.
yacc = 'vendored parser'
""",
  )

  text = text.replace(
    "    yacc_gen.process('src/xkbcomp/parser.y'),",
    """    'src/xkbcomp/parser.c',
    'src/xkbcomp/parser.h',""",
  )

  text = text.replace("'yacc': yacc.full_path() + ' ' + yacc.version(),", "'yacc': yacc,")
  fs.write(meson, text)?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let pc = pm_env.pkg_config_context()?
  patch_vendored_parser()?

  env {
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() "-Ddefault_library=shared" "-Dxkb-config-root=/usr/share/X11/xkb" "-Denable-docs=false" "-Denable-tools=false" "-Denable-x11=false" "-Denable-wayland=false" "-Denable-xkbregistry=false" "-Denable-bash-completion=false" "build" ?
    run $muon "-C" "build" samu "-j1" "libxkbcommon.so.0.11.0" ?

    env {
      DESTDIR = dest
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?

  fs.remove(fp"${dest}/usr/share/bash-completion", missing_ok: true)?
}
