use pm.make as make

export type PkgConfigEnv = {
  pkg_config: Str,
  pkg_config_path: Str,
  pkg_config_libdir: Str,
  pkg_config_sysroot: Str,
  ld_library_path: Str,
}

export proc pkg_config_env() [process, env, error] -> Result[PkgConfigEnv] {
  let pkg_config = process.which("pkg-config")?
  var pkg_config_path = "/usr/lib/pkgconfig:/usr/share/pkgconfig"
  var pkg_config_libdir = pkg_config_path
  var pkg_config_sysroot = ""
  var ld_library_path = fp"${pkg_config.parent.parent}/lib".display()

  match env.Str.LAPUTA_ROOT {
    Ok(root) => {
      if root != "" and root != "/" {
        pkg_config_path = f"${root}/usr/lib/pkgconfig:${root}/usr/share/pkgconfig:${pkg_config_path}"
        pkg_config_libdir = f"${root}/usr/lib/pkgconfig:${root}/usr/share/pkgconfig"
        pkg_config_sysroot = root
        ld_library_path = f"${root}/usr/lib:${ld_library_path}"
      }
    }
    Err(_) => {}
  }

  return {pkg_config: pkg_config.display(), pkg_config_path, pkg_config_libdir, pkg_config_sysroot, ld_library_path}
}

export pure setup_args(options: List[Str]) -> List[Str] {
  return ["setup", "-Dprefix=/usr", "-Dlibdir=lib"].extend(options).push("build")
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
      DESTDIR = dest.display()
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?
}
