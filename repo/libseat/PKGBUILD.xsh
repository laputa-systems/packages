use pm.meson as pm_meson

export let name: Str = "libseat"

export let ver: Str = "0.9.3"

export let rel: Str = "2"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = ["llvm-toolchain", "linux", "muon", "pkgconf"]

export let sources: List[Path] = [p"https://git.sr.ht/~kennylevinsen/seatd/archive/VERSION.tar.gz"]

export let checksums: List[Str] = ["302564d54d8e28191fadfd734f2675ecb0c9e0615a58011b89ef15dfa4dbaa96"]

proc patch_realtime_dependency() [fs, error] {
  let meson = p"meson.build"
  let text = fs.read_text(meson)?

  fs.write_atomic(
    meson,
    text.replace(
      """# needed for cross-compilation
realtime = meson.get_compiler('c').find_library('rt')
private_deps += realtime""",
      """# musl provides realtime interfaces in libc; avoid recording the build-env librt.
realtime = declare_dependency()""",
    ),
  )?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${cpu.count()}"
  let pc = pm_meson.pkg_config_env()?
  patch_realtime_dependency()?

  env {
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" "-Dprefix=/usr" "-Dlibdir=lib" "-Ddefault_library=shared" "-Dwerror=false" "-Dlibseat-logind=disabled" "-Dlibseat-seatd=enabled" "-Dlibseat-builtin=disabled" "-Dserver=disabled" "-Dexamples=disabled" "-Dman-pages=disabled" "build" ?
    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest.display()
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?
}
