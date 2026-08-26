##! Linux package build implementation, intentionally outside the dynamically loaded recipe metadata boundary.
use PKGBUILD-aarch64 as PKGBUILD_aarch64
use PKGBUILD-shared as PKGBUILD_shared
use PKGBUILD-x86_64 as PKGBUILD_x86_64
use kbuild
use linux_config
use parser_gen
use pm.util as pm_util

proc package_arch() [env, error] -> Result[Str] {
  let arch = pm_util.target_arch()?

  if arch == "aarch64" or arch == "x86_64" {
    return arch
  }

  return Err(kbuild.ScriptError.Failed("linux-unsupported-arch", f"unsupported linux package arch ${arch}"))
}

pure linux_srcarch(package_arch_value: Str) -> Result[Str] {
  if package_arch_value == "aarch64" {
    return "arm64"
  }

  if package_arch_value == "x86_64" {
    return "x86"
  }

  return Err(
    kbuild.ScriptError.Failed("linux-unsupported-arch", f"unsupported linux package arch ${package_arch_value}"),
  )
}

pure kernel_config_fragments_for(package_arch_value: Str) -> Result[List[Path]] {
  if package_arch_value == "aarch64" {
    return [p"files/config/aarch64/base-aarch64.fragment"]
  }

  if package_arch_value == "x86_64" {
    return [p"files/config/x86_64/base-x86_64.fragment"]
  }

  return Err(
    kbuild.ScriptError.Failed("linux-unsupported-arch", f"unsupported linux package arch ${package_arch_value}"),
  )
}

pure kernel_image_for(package_arch_value: Str) -> Result[Path] {
  if package_arch_value == "aarch64" {
    return p"arch/arm64/boot/Image"
  }

  if package_arch_value == "x86_64" {
    return p"arch/x86/boot/bzImage"
  }

  return Err(
    kbuild.ScriptError.Failed("linux-unsupported-arch", f"unsupported linux package arch ${package_arch_value}"),
  )
}

proc install_headers_from(root: Path, source: Path, target: Path) [fs, error] {
  if ! fs.exists(source)? {
    return
  }

  let source_root = path.absolute(source)?

  for entry in fs.files(source)? |> where .ext == "h" {
    let header_rel = entry.path.relative_to(source_root)

    fs.install(
      entry.path,
      fp"${root}/${target.display()}/${header_rel.display()}",
      0o644,
      parents: true,
      overwrite: true,
    )?
  }
}

proc install_uapi_headers(dest: Path, srcarch: Str) [fs, error] {
  install_headers_from(dest, p"include/uapi/linux", p"usr/include/linux")?
  install_headers_from(dest, p"include/generated/uapi/linux", p"usr/include/linux")?
  install_headers_from(dest, p"include/uapi/asm-generic", p"usr/include/asm-generic")?
  install_headers_from(dest, fp"arch/${srcarch}/include/uapi/asm", p"usr/include/asm")?
  install_headers_from(dest, fp"arch/${srcarch}/include/generated/uapi/asm", p"usr/include/asm")?
}

proc build_native_scratch(cc: Path, srcarch: Str, version: Str) [fs, process, env, time, error] {
  if srcarch == "arm64" {
    PKGBUILD_aarch64.build_scratch(cc, srcarch, version)?
    return
  }

  if srcarch == "x86" {
    PKGBUILD_x86_64.build_x86_64_scratch(cc, srcarch, version)?
    return
  }

  return Err(
    kbuild.ScriptError.Failed(
      "linux-native-kbuild-unsupported-arch",
      f"native scratch Kbuild final link is only implemented for arm64 and x86; ${srcarch} needs new arch support",
    ),
  )
}

proc build_cc() [fs, process, env, error] -> Result[Path] {
  let root = env.get("XSH_PM_BUILD_ROOT") ?? ""

  if root != "" {
    let cc = fp"${root}/usr/bin/cc"

    if ! fs.exists(cc)? {
      return Err(kbuild.ScriptError.Failed("linux-build-cc", f"missing build-root compiler: ${cc.display()}"))?
    }

    return cc
  }

  return process.which("cc")?
}

proc main(dest: Path) [fs, process, env, time, error] {
  let version = env.get("XSH_PM_VERSION") ?? ""
  let package_start = PKGBUILD_shared.timing_start("package-total")
  let cc = build_cc()?
  let arch = package_arch()?
  let srcarch = linux_srcarch(arch)?
  let config_start = PKGBUILD_shared.timing_start("config")
  let config_fragments = linux_config.resolve_config_fragments(kernel_config_fragments_for(arch)?)?
  linux_config.write_resolved_config(p".", srcarch, config_fragments, p".config")?
  PKGBUILD_shared.timing_done("config", config_start)
  let parser_start = PKGBUILD_shared.timing_start("parser")
  parser_gen.generate_linux_parsers()?
  PKGBUILD_shared.timing_done("parser", parser_start)
  let kbuild_start = PKGBUILD_shared.timing_start("kbuild")
  build_native_scratch(cc, srcarch, version)?
  PKGBUILD_shared.timing_done("kbuild", kbuild_start)
  let install_start = PKGBUILD_shared.timing_start("install")
  let image = kernel_image_for(arch)?
  fs.install(image, fp"${dest}/boot/vmlinuz-${version}", 0o644, parents: true, overwrite: true)?
  fs.install(image, fp"${dest}/boot/vmlinuz", 0o644, parents: true, overwrite: true)?
  fs.install(p".config", fp"${dest}/usr/share/linux/config-${version}", 0o644, parents: true, overwrite: true)?
  install_uapi_headers(dest, srcarch)?
  PKGBUILD_shared.timing_done("install", install_start)
  PKGBUILD_shared.timing_done("package-total", package_start)
}

main(@args)?
