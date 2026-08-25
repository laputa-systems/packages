##! XSH module `PKGBUILD` package and build operations.
use pm.env as pm_env
use pm.make as make

## Exported declaration `name`.
export let name = "freetype"

## Exported declaration `ver`.
export let ver = "2.14.1"

## Exported declaration `rel`.
export let rel = "8"

## Exported declaration `deps`.
export let deps = ["musl", "zlib", "libpng"]

## Exported declaration `mkdeps_host`.
export let mkdeps_host = ["llvm-toolchain", "cmake", "samurai", "pkgconf", "zlib", "libpng"]

## Exported declaration `upstream_sources`.
export let upstream_sources = [
  {
    source: p"https://download-mirror.savannah.gnu.org/releases/freetype/freetype-VERSION.tar.xz",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "32427e8c471ac095853212a37aef816c60b42052d4d9e48230bab3bdf2936ccc",
      },
    ],
  },
]

## Exported declaration `filetree`.
export let filetree = [
  {
    path: p"usr/include/freetype2/dlg/dlg.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/dlg/output.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/config/ftconfig.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/config/ftheader.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/config/ftmodule.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/config/ftoption.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/config/ftstdlib.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/config/integer-types.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/config/mac-support.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/config/public-macros.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/freetype.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftadvanc.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftbbox.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftbdf.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftbitmap.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftbzip2.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftcache.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftchapters.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftcid.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftcolor.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftdriver.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/fterrdef.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/fterrors.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftfntfmt.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftgasp.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftglyph.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftgxval.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftgzip.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftimage.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftincrem.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftlcdfil.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftlist.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftlogging.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftlzw.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftmac.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftmm.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftmodapi.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftmoderr.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftotval.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftoutln.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftparams.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftpfr.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftrender.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftsizes.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftsnames.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftstroke.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftsynth.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftsystem.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/fttrigon.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/fttypes.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ftwinfnt.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/otsvg.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/t1tables.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/ttnameid.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/tttables.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/freetype/tttags.h",
    kind: "file",
  },
  {
    path: p"usr/include/freetype2/ft2build.h",
    kind: "file",
  },
  {
    path: p"usr/lib/cmake/freetype/freetype-config-release.cmake",
    kind: "file",
  },
  {
    path: p"usr/lib/cmake/freetype/freetype-config-version.cmake",
    kind: "file",
  },
  {
    path: p"usr/lib/cmake/freetype/freetype-config.cmake",
    kind: "file",
  },
  {
    path: p"usr/lib/libfreetype.so",
    kind: "symlink",
  },
  {
    path: p"usr/lib/libfreetype.so.6",
    kind: "symlink",
  },
  {
    path: p"usr/lib/libfreetype.so.6.20.4",
    kind: "binary",
  },
  {
    path: p"usr/lib/pkgconfig/freetype2.pc",
    kind: "file",
  },
]

## Exported declaration `build`.
export proc build(dest: Path) [fs, process, env, error] {
  let cmake = process.which("cmake")?
  let samu = process.which("samu")?
  let jobs_flag = f"-j${make.jobs()?}"
  let target_root = env.get("LAPUTA_ROOT") ?? "/"

  var cmake_args = [
    "-S",
    ".",
    "-B",
    "build",
    "-G",
    "Ninja",
    "-DCMAKE_BUILD_TYPE=Release",
    pm_env.cmake_install_prefix_arg(),
    pm_env.cmake_install_libdir_arg(),
    "-DBUILD_SHARED_LIBS=ON",
    "-DFT_REQUIRE_ZLIB=ON",
    "-DFT_REQUIRE_PNG=ON",
    "-DFT_DISABLE_BZIP2=ON",
    "-DFT_DISABLE_BROTLI=ON",
    "-DFT_DISABLE_HARFBUZZ=ON",
  ]

  if target_root != "" and target_root != "/" {
    cmake_args = cmake_args.extend(
      [
        f"-DZLIB_LIBRARY=${target_root}/usr/lib/libz.so",
        f"-DZLIB_INCLUDE_DIR=${target_root}/usr/include",
        f"-DPNG_LIBRARY=${target_root}/usr/lib/libpng.so",
        f"-DPNG_PNG_INCLUDE_DIR=${target_root}/usr/include",
      ],
    )
  }

  run $cmake @cmake_args ?
  run $samu "-C" "build" $jobs_flag ?

  env {
    DESTDIR = dest
  } {
    cd build {
      run $cmake "-P" "cmake_install.cmake" ?
    }
  } ?

  fs.remove(fp"${dest}/usr/share/aclocal", missing_ok: true)?
  fs.remove(fp"${dest}/usr/share/man", missing_ok: true)?
}
