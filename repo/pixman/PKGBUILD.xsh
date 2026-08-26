##! Package recipe metadata and build operations.
use pm.env as pm_env
use pm.util as pm_util

## Package recipe export.
export let name = "pixman"

## Explicit payload or metapackage classification.
export let package_kind = "payload"

## Package recipe export.
export let ver = "0.46.4"

## Package recipe export.
export let rel = "10"

## Package recipe export.
export let deps = ["musl"]

## Package recipe export.
export let mkdeps_host = ["llvm-toolchain", "muon", "pkgconf", "samurai"]

## Package recipe export.
export let upstream_sources = [
  {
    source: p"https://xorg.freedesktop.org/releases/individual/lib/pixman-VERSION.tar.xz",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "a098c33924754ad43f981b740f6d576c70f9ed1006e12221b1845431ebce1239",
      },
    ],
  },
]

## Package recipe export.
export let filetree = [
  {
    path: p"usr/lib/libpixman-1.so.0",
    kind: "symlink",
  },
  {
    path: p"usr/lib/libpixman-1.so.0.46.4",
    kind: "binary",
  },
]

# Musl provides libm through libc.  Letting Meson discover the staged libm
# symlink records the executor-local build root as an ELF dependency; link by
# name so the installed library instead resolves through the target libc.
proc patch_musl_math() [fs, error] {
  let meson = p"meson.build"

  fs.write(
    meson,
    meson.read_text()?.replace(
      "dep_m = cc.find_library('m', required : false)",
      "dep_m = declare_dependency(link_args : ['-lm'])",
    ),
  )?
}

## Package recipe export.
export proc build(dest: Path) [fs, process, env, error] {
  let jobs_flag = f"-j${cpu.count()}"
  let arch = pm_util.target_arch()?
  patch_musl_math()?

  if arch == "x86_64" {
    run "muon" "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() "-Ddefault_library=shared" "-Dlibpng=disabled" "-Dgtk=disabled" "-Dtests=disabled" "-Ddemos=disabled" "build" ?
  } else {
    run "muon" "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() "-Ddefault_library=shared" "-Dlibpng=disabled" "-Dgtk=disabled" "-Dtests=disabled" "-Ddemos=disabled" "-Dmmx=disabled" "-Dsse2=disabled" "-Dssse3=disabled" "build" ?
  }

  run "muon" "-C" "build" samu $jobs_flag ?

  env {
    DESTDIR = dest
  } {
    run "muon" "-C" "build" install ?
  } ?

  fs.remove(fp"${dest}/usr/include", missing_ok: true)?
  fs.remove(fp"${dest}/usr/lib/pkgconfig", missing_ok: true)?
  fs.remove(fp"${dest}/usr/lib/libpixman-1.so", missing_ok: true)?
}
