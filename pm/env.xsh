export type PkgConfigContext = {
  pkg_config: Path,
  pkg_config_path: Str,
  pkg_config_libdir: Str,
  pkg_config_sysroot: Str,
  ld_library_path: Str,
}

export let prefix: Path = /usr

export let sysconfdir: Path = /etc

export let localstatedir: Path = /var

export let libdir_name: Str = "lib"

export let libexecdir_name: Str = "libexec"

export let bindir: Path = /usr/bin

export let includedir: Path = /usr/include

export let libdir: Path = /usr/lib

export let mandir: Path = /usr/share/man

export pure meson_prefix_arg() -> Str {
  f"-Dprefix=${prefix}"
}

export pure meson_libdir_arg() -> Str {
  f"-Dlibdir=${libdir_name}"
}

export pure meson_sysconfdir_arg() -> Str {
  f"-Dsysconfdir=${sysconfdir}"
}

export pure meson_localstatedir_arg() -> Str {
  f"-Dlocalstatedir=${localstatedir}"
}

export pure cmake_install_prefix_arg() -> Str {
  f"-DCMAKE_INSTALL_PREFIX=${prefix}"
}

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

export pure build_path(root: Path, current: Str) -> Str {
  if root_is_empty(root) {
    return current
  }

  let tool_bin = rooted(root, "/usr/lib/llvm-toolchain/bin")
  let usr_bin = rooted(root, "/usr/bin")
  return f"${tool_bin}:${usr_bin}:${current}"
}

export pure build_ld_library_path(root: Path, current: Str = "") -> Str {
  if root_is_empty(root) {
    return current
  }

  if current == "" {
    let lib = rooted(root, "/usr/lib")
    let llvm_lib = rooted(root, "/usr/lib/llvm22/lib")
    return f"${lib}:${llvm_lib}"
  }

  let lib = rooted(root, "/usr/lib")
  let llvm_lib = rooted(root, "/usr/lib/llvm22/lib")
  return f"${lib}:${llvm_lib}:${current}"
}

export proc target_root() [env] -> Path {
  fp"${env.get("LAPUTA_ROOT") ?? ""}"
}

export proc build_root() [env] -> Path {
  let value = (env.get("XSH_PM_BUILD_ROOT") ?? "").trim()

  if value != "" {
    return fp"${value}"
  }

  return target_root()
}

export proc build_path_env(root: Path) [env] -> Str {
  return build_path(root, env.get("PATH") ?? "")
}

export proc build_ld_library_path_env(root: Path) [env] -> Str {
  return build_ld_library_path(root, env.get("LD_LIBRARY_PATH") ?? "")
}

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
