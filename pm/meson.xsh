use pm.env as pm_env
use pm.make as make

export proc pkg_config_env() [process, env, error] -> Result[pm_env.PkgConfigContext] {
  return pm_env.pkg_config_context()?
}

export pure setup_args(options: List[Str]) -> List[Str] {
  return ["setup", pm_env.meson_prefix_arg(), pm_env.meson_libdir_arg()].extend(options).push("build")
}

proc muon_build(dest: Path, options: List[Str], jobs_count: Int = 0) [process, env, error] {
  let muon = process.which("muon")?
  let jobs = if jobs_count > 0 { jobs_count } else { make.jobs()? }
  let jobs_flag = f"-j${jobs}"
  let pc = pkg_config_env()?
  let setup = setup_args(options)

  env {
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon @setup ?
    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?
}
