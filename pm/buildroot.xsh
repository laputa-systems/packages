use local
use types
use util

export proc local_package_names(packages: List[Package]) [] -> Map[Bool] {
  var names = {pkg.name: true for pkg in packages}
  names
}

export proc missing_dependency_names(
  root: Path,
  packages: List[Package],
  include_mkdeps: Bool,
  local_names: Map[Bool],
) [fs, error] -> Result[List[Str]] {
  var names: List[Str] = []
  var seen: Map[Bool] = {}

  for pkg in packages {
    var deps = pkg.deps

    if include_mkdeps {
      deps = deps.extend(pkg.mkdeps)
      deps = deps.extend(pkg.target_build_deps)
    }

    for dep in deps {
      if ! local_names.get(dep, false) and ! seen.get(dep, false) and ! fs.exists(package_db_path(root, dep))? {
        names = names.push(dep)
        seen[dep] = true
      }
    }
  }

  names
}

export proc install_remote_dependency_set(ctx: PmContext, names: List[Str]) [fs, net, process, env, time, error] {
  if names.len() > 0 {
    install_remote_packages(ctx, names)?
  }
}

export proc install_remote_dependency_set_for_arch(
  ctx: PmContext,
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

export proc install_chroot_base(
  ctx: PmContext,
  local_names: Map[Bool],
  include_tool_runtime: Bool,
) [fs, net, process, env, time, error] {
  if (env.get("XSH_PM_BUILD_CHROOT") ?? "1") == "0" {
    return
  }

  if ! local_names.get("baselayout", false) {
    install_remote_dependency_set(ctx, ["baselayout"])?
  }

  if ! local_names.get("laputa-pm", false) and ! local_names.get("xsh", false) {
    install_remote_dependency_set(ctx, ["laputa-pm"])?
  }

  if include_tool_runtime {
    install_remote_dependency_set(ctx, ["musl", "zlib", "llvm-toolchain"])?
  }
}

export proc install_chroot_base_for_arch(
  ctx: PmContext,
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
