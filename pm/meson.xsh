##! PM meson operations and shared package-manager policy.
use pm.env as pm_env
use pm.make as make

## Exported PM declaration `pkg_config_env`.
export proc pkg_config_env() [process, env, error] -> Result[pm_env.PkgConfigContext] {
  return pm_env.pkg_config_context()?
}

## Exported PM declaration `setup_args`.
export pure setup_args(options: List[Str]) -> List[Str] {
  return ["setup", pm_env.meson_prefix_arg(), pm_env.meson_libdir_arg()].extend(options).push("build")
}
