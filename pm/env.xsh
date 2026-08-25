##! PM environment paths and toolchain variables.
## The exported paths define the package build filesystem contract.
## Environment values needed to invoke pkg-config under a package root.
export type PkgConfigContext = {
  pkg_config: Path,
  pkg_config_path: Str,
  pkg_config_libdir: Str,
  pkg_config_sysroot: Str,
  ld_library_path: Str,
}

## Exported PM declaration `prefix`.
export let prefix = /usr

## Exported PM declaration `sysconfdir`.
export let sysconfdir = /etc

## Exported PM declaration `localstatedir`.
export let localstatedir = /var

## Exported PM declaration `libdir_name`.
export let libdir_name = "lib"

## Exported PM declaration `libexecdir_name`.
export let libexecdir_name = "libexec"

## Exported PM declaration `bindir`.
export let bindir = /usr/bin

## Exported PM declaration `includedir`.
export let includedir = /usr/include

## Exported PM declaration `libdir`.
export let libdir = /usr/lib

## Exported PM declaration `mandir`.
export let mandir = /usr/share/man

## Exported PM declaration `meson_prefix_arg`.
export pure meson_prefix_arg() -> Str {
  f"-Dprefix=${prefix}"
}

## Exported PM declaration `meson_libdir_arg`.
export pure meson_libdir_arg() -> Str {
  f"-Dlibdir=${libdir_name}"
}

## Exported PM declaration `meson_sysconfdir_arg`.
export pure meson_sysconfdir_arg() -> Str {
  f"-Dsysconfdir=${sysconfdir}"
}

## Exported PM declaration `meson_localstatedir_arg`.
export pure meson_localstatedir_arg() -> Str {
  f"-Dlocalstatedir=${localstatedir}"
}

## Exported PM declaration `cmake_install_prefix_arg`.
export pure cmake_install_prefix_arg() -> Str {
  f"-DCMAKE_INSTALL_PREFIX=${prefix}"
}

## Exported PM declaration `cmake_install_libdir_arg`.
export pure cmake_install_libdir_arg() -> Str {
  f"-DCMAKE_INSTALL_LIBDIR=${libdir_name}"
}

pure root_is_empty(root: Path) -> Bool {
  return root == fp""
}

pure root_is_system(root: Path) -> Bool {
  return root == /
}

pure rooted(root: Path, rel: Str) -> Str {
  if root_is_system(root) {
    return rel
  }

  return f"${root}${rel}"
}

## Exported PM declaration `build_path`.
export pure build_path(root: Path, current: Str) -> Str {
  if root_is_empty(root) {
    return current
  }

  let tool_bin = rooted(root, "/usr/lib/llvm-toolchain/bin")
  let usr_bin = rooted(root, "/usr/bin")
  return f"${tool_bin}:${usr_bin}:${current}"
}

## Exported PM declaration `build_ld_library_path`.
export pure build_ld_library_path(root: Path, current: Str = "") -> Str {
  if root_is_empty(root) {
    return current
  }

  if current == "" {
    let lib = rooted(root, "/usr/lib")
    let llvm_lib = rooted(root, "/usr/lib/llvm23/lib")
    return f"${lib}:${llvm_lib}"
  }

  let lib = rooted(root, "/usr/lib")
  let llvm_lib = rooted(root, "/usr/lib/llvm23/lib")
  return f"${lib}:${llvm_lib}:${current}"
}

## Exported PM declaration `target_root`.
export proc target_root() [env] -> Path {
  fp"${env.get("LAPUTA_ROOT") ?? ""}"
}

## Exported PM declaration `build_root`.
export proc build_root() [env] -> Path {
  let value = (env.get("XSH_PM_BUILD_ROOT") ?? "").trim()

  if value != "" {
    return fp"${value}"
  }

  return target_root()
}

## Exported PM declaration `build_path_env`.
export proc build_path_env(root: Path) [env] -> Str {
  return build_path(root, env.get("PATH") ?? "")
}

## Exported PM declaration `build_ld_library_path_env`.
export proc build_ld_library_path_env(root: Path) [env] -> Str {
  return build_ld_library_path(root, env.get("LD_LIBRARY_PATH") ?? "")
}

## Exported PM declaration `pkg_config_context`.
export proc pkg_config_context() [process, env, error] -> Result[PkgConfigContext] {
  let pkg_config = process.which("pkg-config")?
  var pkg_config_path = f"${libdir}/pkgconfig:/usr/share/pkgconfig"
  var pkg_config_libdir = pkg_config_path
  var pkg_config_sysroot = ""
  var ld_library_path = f"${pkg_config.parent.parent}/lib"
  let root = target_root()

  if ! root_is_empty(root) and ! root_is_system(root) {
    pkg_config_path = f"${root}/usr/lib/pkgconfig:${root}/usr/share/pkgconfig:${pkg_config_path}"
    pkg_config_libdir = f"${root}/usr/lib/pkgconfig:${root}/usr/share/pkgconfig"
    pkg_config_sysroot = f"${root}"
    ld_library_path = f"${root}/usr/lib:${ld_library_path}"
  }

  return {pkg_config, pkg_config_path, pkg_config_libdir, pkg_config_sysroot, ld_library_path}
}
