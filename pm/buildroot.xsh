##! PM buildroot operations and shared package-manager policy.
use install
use local
use types
use util

## Exported PM declaration `local_package_names`.
export proc local_package_names(packages: List[types.Package]) [] -> Map[Bool] {
  var names = {pkg.name: true for pkg in packages}
  names
}

## Exported PM declaration `missing_dependency_names`.
export proc missing_dependency_names(
  root: Path,
  packages: List[types.Package],
  include_mkdeps_host: Bool,
  local_names: Map[Bool],
) [fs, error] -> Result[List[Str]] {
  var names = []
  var seen: Map[Bool] = {}

  for pkg in packages {
    var deps = pkg.deps

    if include_mkdeps_host {
      deps = deps.extend(pkg.mkdeps_host)
      deps = deps.extend(pkg.mkdeps_target)
    }

    for dep in deps {
      if ! local_names.get(dep, false) and ! seen.get(dep, false) and ! fs.exists(util.package_db_path(root, dep))? {
        names = names.push(dep)
        seen[dep] = true
      }
    }
  }

  names
}

## Exported PM declaration `install_remote_dependency_set`.
export proc install_remote_dependency_set(ctx: types.PmContext, names: List[Str]) [fs, net, process, env, time, error] {
  if names.len() > 0 {
    install.install_remote_packages(ctx, names)?
  }
}

## Exported PM declaration `install_remote_dependency_set_for_arch`.
export proc install_remote_dependency_set_for_arch(
  ctx: types.PmContext,
  names: List[Str],
  arch: Str,
) [fs, net, process, env, time, error] {
  env {
    XSH_PM_ARCH = arch
    XSH_PM_TARGET_ARCH = arch
  } {
    install_remote_dependency_set(ctx, names)?
  } ?
}

## Exported PM declaration `install_chroot_base`.
export proc install_chroot_base(
  ctx: types.PmContext,
  local_names: Map[Bool],
  include_tool_runtime: Bool,
) [fs, net, process, env, time, error] {
  if (env.get("XSH_PM_BUILD_CHROOT") ?? "1") == "0" {
    return
  }

  var names: List[Str] = []

  if ! local_names.get("baselayout", false) {
    names = names.push("baselayout")
  }

  if ! local_names.get("laputa-pm", false) and ! local_names.get("xsh", false) {
    names = names.push("laputa-pm")
  }

  if include_tool_runtime {
    names = names.extend(["musl", "zlib"])
  }

  install_remote_dependency_set(ctx, names)?
}

## Exported PM declaration `install_chroot_base_for_arch`.
export proc install_chroot_base_for_arch(
  ctx: types.PmContext,
  local_names: Map[Bool],
  include_tool_runtime: Bool,
  arch: Str,
) [fs, net, process, env, time, error] {
  env {
    XSH_PM_ARCH = arch
    XSH_PM_TARGET_ARCH = arch
  } {
    install_chroot_base(ctx, local_names, include_tool_runtime)?
  } ?
}
