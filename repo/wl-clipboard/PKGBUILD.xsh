use pm.make as make
use pm.util as pm_util
use pm.meson as pm_meson

export let name: Str = "wl-clipboard"

export let ver: Str = "2.3.0"

export let rel: Str = "2"

export let deps: List[Str] = ["musl", "wayland-libs-client"]

export let mkdeps: List[Str] = [
  "llvm-toolchain",
  "muon",
  "pkgconf",
  "wayland-dev",
  "wayland-protocols",
  "wayland-libs-client",
]

export let target_build_deps: List[Str] = ["wayland-dev", "wayland-protocols"]

export let sources: List[Path] = [p"https://github.com/bugaevc/wl-clipboard/archive/refs/tags/vVERSION.tar.gz"]

export let checksums: List[Str] = ["b4dc560973f0cd74e02f817ffa2fd44ba645a4f1ea94b7b9614dacc9f895f402"]

proc patch_optional_installs() [fs, error] {
  fs.write(p"data/meson.build", "")?
  fs.write(p"completions/meson.build", "")?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${make.jobs()?}"
  let pc = pm_meson.pkg_config_env()?
  let build_root = env.get("XSH_PM_BUILD_ROOT") ?? ""
  let native_scanner = pm_util.build_arch()? != pm_util.target_arch()? and build_root != ""
  patch_optional_installs()?

  env {
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" "-Dprefix=/usr" "-Dlibdir=lib" "-Ddefault_library=static" "-Dprotocols=enabled" "-Dzshcompletiondir=no" "-Dfishcompletiondir=no" "build" ?
    if native_scanner {
      let native_scanner_wrapper = fp"${fs.cwd()?}/build/wayland-scanner-native-wrapper"
      fs.write(native_scanner_wrapper, f"""#!/bin/sh
LD_LIBRARY_PATH="${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib"
export LD_LIBRARY_PATH
exec "${build_root}/usr/bin/wayland-scanner" "$@"
""")?
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

  fs.remove(fp"${dest}/usr/share/man", missing_ok: true)?
}
