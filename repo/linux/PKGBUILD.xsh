use PKGBUILD-aarch64 as PKGBUILD_aarch64
use PKGBUILD-x86_64 as PKGBUILD_x86_64
use kbuild
use linux_config
use parser_gen
use pm.util as pm_util

export let name = "linux"

export let ver = "7.0.5"

export let rel = "32"

export let deps: List[Str] = []

export let mkdeps = ["llvm-toolchain", "flex", "bison"]

export let nostrip = true

export let sources = [
  p"https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.0.5.tar.xz",
  p"files/config/aarch64/base-aarch64.fragment",
  p"files/config/x86_64/base-x86_64.fragment",
  p"files/sysreg-defs.h",
  p"files/generated/timeconst.h",
  p"files/generated/bounds.h",
  p"files/generated/asm-offsets.h",
  p"files/generated/rq-offsets.h",
  p"files/generated/sha256-core.S",
  p"files/generated/sha512-core.S",
  p"files/generated/cpufeaturemasks-x86.h",
  p"files/generated/x86-alternative-stubs.h",
  p"files/generated/inat-tables-x86.c",
  p"files/x86-jump-label-patch.c",
]

export let checksums = [
  "965fb0a1c1675399fc60c6063b227c0523041b5f9a662b66462f1212c438ac3c",
  "4ae5a43efcd369d8e457053c2279362df70e6d39820a4f5a2a5988e6d2bc15ba",
  "d7db8438d9840892bc6e491df49d580c5e7ec74d287087c51bdcdeb6017cc4cc",
  "7578877f5978e66b4ac04d66a2fcdbd6d183ae56d2786f4538d32af0c477e317",
  "664c2e5a8ed45eb327f0f1b1ee83249a24f98ee67f3bcb313a4d0bf99202ceed",
  "c7daffc2aa5a964969421942bb000e65a2b9866d2a2a11529689c379005ef1f1",
  "bf747255377b322ae454423b1af409d30740196b3403f42ca5b7a38e2549ccb4",
  "01f07c33f1d15437c763a3bc0a9a8437a0404f6fbef80ef9781698e0d47cf8d4",
  "1b7d66d6d221e3663be0da7d0516564e6d5d10c07e8c0612ee0ac87bcb9dc519",
  "527009fbdd1faa79dee68028a3fd92440412c24e29ec95b32718f911216d27ec",
  "fb569e0a080248ddba05c62f450de98b4916190c9c3bea49afb12dc1e5b95fe9",
  "8233e16fc51b623088d439051bc895dc8275d7a4f2f3bd640eb1acc35a888af8",
  "5bc098c57c3bfaa8d3fbd05f6d7703c5573417431a48160a194961e7cf334525",
  "39fa47de004dc15b2d71fad9256734992f93743cdb65ef1a70d454b0403f5031",
]

proc package_arch() [env, error] -> Result[Str] {
  let arch = pm_util.target_arch()?

  if arch == "aarch64" or arch == "x86_64" {
    return arch
  }

  return Err(ScriptError.Failed("linux-unsupported-arch", f"unsupported linux package arch ${arch}"))
}

pure linux_srcarch(package_arch_value: Str) -> Result[Str] {
  if package_arch_value == "aarch64" {
    return "arm64"
  }

  if package_arch_value == "x86_64" {
    return "x86"
  }

  return Err(ScriptError.Failed("linux-unsupported-arch", f"unsupported linux package arch ${package_arch_value}"))
}

pure kernel_config_fragments_for(package_arch_value: Str) -> Result[List[Path]] {
  if package_arch_value == "aarch64" {
    return [p"files/config/aarch64/base-aarch64.fragment"]
  }

  if package_arch_value == "x86_64" {
    return [p"files/config/x86_64/base-x86_64.fragment"]
  }

  return Err(ScriptError.Failed("linux-unsupported-arch", f"unsupported linux package arch ${package_arch_value}"))
}

proc build_kernel_config_fragments_for(package_arch_value: Str) [fs, error] -> Result[List[Path]] {
  var fragments: List[Path] = []

  for source_fragment in kernel_config_fragments_for(package_arch_value)? {
    let package_fragment = fp"../pkg/${source_fragment.display()}"

    if package_fragment.exists()? {
      fragments = fragments.push(package_fragment)
    } else {
      fragments = fragments.push(source_fragment)
    }
  }

  return fragments
}

pure kernel_image_for(package_arch_value: Str) -> Result[Path] {
  if package_arch_value == "aarch64" {
    return p"arch/arm64/boot/Image"
  }

  if package_arch_value == "x86_64" {
    return p"arch/x86/boot/bzImage"
  }

  return Err(ScriptError.Failed("linux-unsupported-arch", f"unsupported linux package arch ${package_arch_value}"))
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

proc build_native_scratch(cc: Path, srcarch: Str) [fs, process, env, error] {
  if srcarch == "arm64" {
    PKGBUILD_aarch64.build_scratch(cc, srcarch, ver)?
    return
  }

  if srcarch == "x86" {
    PKGBUILD_x86_64.build_x86_64_scratch(cc, srcarch, ver)?
    return
  }

  return Err(
    ScriptError.Failed(
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
      return Err(ScriptError.Failed("linux-build-cc", f"missing build-root compiler: ${cc.display()}"))?
    }

    return cc
  }

  return process.which("cc")?
}

export proc build(dest: Path) [fs, process, env, error] {
  let cc = build_cc()?
  let arch = package_arch()?
  let srcarch = linux_srcarch(arch)?
  linux_config.write_resolved_config(p".", srcarch, build_kernel_config_fragments_for(arch)?, p".config")?
  parser_gen.generate_linux_parsers()?
  build_native_scratch(cc, srcarch)?
  let image = kernel_image_for(arch)?
  fs.install(image, fp"${dest}/boot/vmlinuz-${ver}", 0o644, parents: true, overwrite: true)?
  fs.install(image, fp"${dest}/boot/vmlinuz", 0o644, parents: true, overwrite: true)?
  fs.install(p".config", fp"${dest}/usr/share/linux/config-${ver}", 0o644, parents: true, overwrite: true)?
  install_uapi_headers(dest, srcarch)?
}

export let filetree = [
  {path: p"boot", kind: "tree"},
  {path: p"usr", kind: "tree"},
]
