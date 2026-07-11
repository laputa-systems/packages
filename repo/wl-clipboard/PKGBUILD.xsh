use pm.env as pm_env
use pm.make as make
use pm.util as pm_util

export let name = "wl-clipboard"

export let ver = "2.3.0"

export let rel = "6"

export let deps = ["musl", "wayland-libs-client"]

export let mkdeps = [
  "llvm-toolchain",
  "muon",
  "samurai",
  "pkgconf",
  "wayland-dev",
  "wayland-protocols",
  "wayland-libs-client",
]

export let target_build_deps = ["wayland-dev", "wayland-protocols"]

export let sources = [p"https://github.com/bugaevc/wl-clipboard/archive/refs/tags/vVERSION.tar.gz"]

export let checksums = [
  "b4dc560973f0cd74e02f817ffa2fd44ba645a4f1ea94b7b9614dacc9f895f402",
]

proc patch_optional_installs() [fs, error] {
  fs.write(p"data/meson.build", "")?
  fs.write(p"completions/meson.build", "")?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${make.jobs()?}"
  let pc = pm_env.pkg_config_context()?
  let build_root = env.get("XSH_PM_BUILD_ROOT") ?? ""
  let native_scanner = pm_util.build_arch()? != pm_util.target_arch()? and build_root != ""

  let native_tools_ld = if native_scanner {
    f"${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib:${pc.ld_library_path}"
  } else {
    pc.ld_library_path
  }

  patch_optional_installs()?

  env {
    LD_LIBRARY_PATH = native_tools_ld
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" pm_env.meson_prefix_arg() pm_env.meson_libdir_arg() "-Ddefault_library=static" "-Dprotocols=enabled" "-Dzshcompletiondir=no" "-Dfishcompletiondir=no" "build" ?

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

  fs.remove(fp"${dest}/usr/share/man", missing_ok: true)?
}

export let filetree = [
  {path: p"usr/bin/wl-copy", kind: "binary"},
  {path: p"usr/bin/wl-paste", kind: "binary"},
]
