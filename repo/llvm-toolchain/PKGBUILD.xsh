use pm.util as pm_util

error LlvmToolchainError = Failed(message: Str)

export let name: Str = "llvm-toolchain"

export let ver: Str = "22.1.8"

export let rel: Str = "3"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = []

export let nostrip: Bool = true

export let sources: List[Path] = [
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/clang22-22.1.8-r0.apk => clang22.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/clang22-headers-22.1.8-r0.apk => clang22-headers.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/clang22-libs-22.1.8-r0.apk => clang22-libs.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/compiler-rt-22.1.8-r0.apk => compiler-rt.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/lld22-22.1.8-r0.apk => lld22.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/lld22-libs-22.1.8-r0.apk => lld22-libs.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/llvm22-22.1.8-r0.apk => llvm22.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/llvm22-libs-22.1.8-r0.apk => llvm22-libs.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/llvm22-dev-22.1.8-r0.apk => llvm22-dev.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/llvm22-linker-tools-22.1.8-r0.apk => llvm22-linker-tools.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/libstdc++-15.2.0-r6.apk => libstdcxx.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/libstdc++-dev-15.2.0-r6.apk => libstdcxx-dev.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/libgcc-15.2.0-r6.apk => libgcc.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/libffi-3.5.2-r1.apk => libffi.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/zstd-libs-1.5.7-r2.apk => zstd-libs.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/libxml2-2.13.9-r2.apk => libxml2.tar.gz",
  p"https://dl-cdn.alpinelinux.org/alpine/edge/main/ARCH/xz-libs-5.8.3-r0.apk => xz-libs.tar.gz",
  p"files/generated/libgcc_s-aarch64.so.1 => generated-libgcc-aarch64",
  p"files/generated/libgcc_s-x86_64.so.1 => generated-libgcc-x86_64",
]

export let checksums: List[Str] = [
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
  "SKIP",
]

export let checksums_aarch64: List[Str] = [
  "248c3fb7827fe591a5bf28ba0d567cce235c1395e49d35108eed7892c6c51f53",
  "9b646282d9c66266a45bd53ac97d79a5d5aaccfe08454ea11800fed2f01114cf",
  "27f54a9838e012523b0b42a6b398c5af55fde571d4f4e06c8e1e4ec29fb67747",
  "e34e80b588ed96d5552fdd58b6adeb112e1c2f1f5dffb9ea1f84fbf8043f85a2",
  "06b36012563bb8e8f2a13bc80be9ac87dac96b14bd330b7084bb8896e8458f08",
  "44031121030d1b32fa878f2c80b5cdb3f067d1ab771df388830150837506b6c6",
  "30f52ee878bfc1e21bcbc901393f915bcccac04f4e606406b892ad460309e0de",
  "ccf81493d2468b95df937248f3b2bf0c86eed57ab2573e2caa97381cf1b0c0b6",
  "ff1b65e02b46749d50069a4f8724a2920f7bf2cf79827f480923bf26af483f0f",
  "db4fe23832595402a3ea407e6ea5b08817414c16231b7cada0592bfb1524b675",
  "afa90864c427373ccb216644c6dd0c56e318269ddda62cb756e5350e426b5a5f",
  "17114209cea6ec992c6b332e0c4c9fcaaa2df721d2918e4905bf37a5f35e9471",
  "e62f234bf2405dd2f968165e19e4a56a03430a0634bbd26848ae4d150505ee80",
  "bff86f6c3fc29e87fb8741b6a05602e6268a7f8cbefa48ec53d6f7fcfd00ff02",
  "67f0803cc07bad0dd866d21fdaca1fa742b541a4e5e96e0159bd8b0054d348ac",
  "27c1a195517714c358c9f8c8dd33ec5d0fcc2b47f44c638a487c2a185e0b00af",
  "b139f4c3747b46dd1461592cfe4a0d3e6daf010d7376691092968d6f69cb1612",
  "SKIP",
  "SKIP",
]

export let checksums_x86_64: List[Str] = [
  "567059b3da3fcac554012143a67268cc14ed0122f15c76b5439dd655f074cc62",
  "5fe1814ec6548850f0e3bbcfa49e2e579b1e0181dd435a2ee437f71977a39400",
  "f54f9d903e8bbd2ae496b15e74cb671a4c9ac4242c253d25696359f619309ede",
  "54aef124308d63bf26463293e25045be5449252c0e031ae340966d597fb61d0f",
  "01194a5d4ef62d152c8737329f8553846f4566b81406031049f5b7e9ee14b5cf",
  "0dc5d7e41edefcd672e1d3fff3a074db790efd04f24cf7c138e1b711dd5da479",
  "f6f550ecc0def8014575899e2a82b1b9f41cddbebbea658cc3674ddc6e453118",
  "67e5198d42f07838a3be6c5fd91c043040116b5ed381ebc0f09b2c18a2e4d7e2",
  "3c4d63c1a199a674cacfc05e549d4d95855cb222f41eac558b907efbfe968c39",
  "f0fb2810d8c7a14371e423d551ba593053a6566420796fedd63579b6d65fcc8b",
  "30395074c46375d870b8ff5ff333d3fcce1855a9981324d43dbf69da6c06ad2a",
  "1d89eba28210e543b87253071f257dc4070a33e279875950889cbcadfbb12bef",
  "d285c3e251486004567c47353be986145a58c1f6761c6fae829c1a7e0a6b068f",
  "0ab19290ba2a4aea64613c16b9744853363cbd7a61159860eaf4bd255d470f56",
  "5025e2207b44a131f1b2262761187d88500829c2171d566d37a1225246fe542e",
  "4b2f986159c659f014b942fe8a5d70c67af475153ca826c3dd53389eea46a300",
  "95162110d7b67e3e2fd243fa4a43f75170a9c4839c47f86bb5e34340a6dfe930",
  "SKIP",
  "SKIP",
]

pure bool_literal(value: Bool) -> Str {
  if value {
    return "true"
  }

  return "false"
}

pure xsh_wrapper_source(real: Path, clang: Bool, cxx: Bool) -> Str {
  let template = r"""#!/usr/local/bin/xsh
proc has_arg(argv: List[Str], needle: Str) [] -> Bool {
  for arg in argv {
    if arg == needle {
      return true
    }
  }

  return false
}

proc has_option_prefix(argv: List[Str], prefix: Str) [] -> Bool {
  for arg in argv {
    if arg.starts_with(prefix) {
      return true
    }
  }

  return false
}

proc compile_only(argv: List[Str]) [] -> Bool {
  return has_arg(argv, "-c") or has_arg(argv, "-S") or has_arg(argv, "-E")
}

proc shared_link(argv: List[Str]) [] -> Bool {
  return has_arg(argv, "-shared")
}

proc static_link(argv: List[Str]) [] -> Bool {
  return has_arg(argv, "-static")
}

proc default_runtime(argv: List[Str]) [] -> Bool {
  return ! has_arg(argv, "-nostdlib") and ! has_arg(argv, "-nodefaultlibs")
}

proc default_startfiles(argv: List[Str]) [] -> Bool {
  return default_runtime(argv) and ! has_arg(argv, "-nostartfiles")
}

proc include_controlled(argv: List[Str]) [] -> Bool {
  return has_arg(argv, "-nostdinc") or has_arg(argv, "-nostdlibinc") or has_arg(argv, "-nostdsysteminc")
}

proc sysroot_arg(argv: List[Str]) [error] -> Result[Path] {
  var index = 0

  while index < argv.len() {
    let arg = argv[index]

    if arg == "--sysroot" and index + 1 < argv.len() {
      return Path.parse(argv[index + 1])?
    }

    if arg.starts_with("--sysroot=") {
      return Path.parse(arg.replace("--sysroot=", ""))?
    }

    index += 1
  }

  return p"/"
}

proc rooted(root: Path, rel: Str) [error] -> Result[Path] {
  if root.display() == "/" {
    return Path.parse(f"/${rel}")?
  }

  fp"${root}/${rel}"
}

proc source_like(arg: Str) [] -> Bool {
  return arg.ends_with(".c") or arg.ends_with(".cc") or arg.ends_with(".cpp") or arg.ends_with(".cxx") or arg.ends_with(".C") or arg.ends_with(".S")
}

proc needs_frontend_flags(argv: List[Str]) [] -> Bool {
  if has_arg(argv, "-E") {
    return true
  }

  var index = 0
  var explicit_assembler = false

  while index < argv.len() {
    let arg = argv[index]

    if arg == "-x" and index + 1 < argv.len() {
      explicit_assembler = argv[index + 1] == "assembler"
      index += 2
      continue
    }

    if arg.starts_with("-") {
      if ["-o", "-MF", "-MT", "-MQ", "-include", "-isystem"].contains(arg) and index + 1 < argv.len() {
        index += 2
      } else {
        index += 1
      }
      continue
    }

    if ! explicit_assembler and source_like(arg) {
      return true
    }

    index += 1
  }

  return false
}

proc arch_from_triple(triple: Str) [] -> Str {
  if triple.starts_with("aarch64") or triple.starts_with("arm64") {
    return "aarch64"
  }

  if triple.starts_with("x86_64") or triple.starts_with("amd64") {
    return "x86_64"
  }

  return ""
}

proc host_arch() [env, error] -> Result[Str] {
  let os = system.uname()?

  if os.machine == "arm64" {
    return "aarch64"
  }

  if os.machine == "amd64" {
    return "x86_64"
  }

  return os.machine
}

proc target_arch(argv: List[Str]) [env, error] -> Result[Str] {
  var index = 0

  while index < argv.len() {
    let arg = argv[index]

    if (arg == "-target" or arg == "--target") and index + 1 < argv.len() {
      let arch = arch_from_triple(argv[index + 1])

      if arch != "" {
        return arch
      }

      index += 2
      continue
    }

    if arg.starts_with("--target=") {
      let arch = arch_from_triple(arg.replace("--target=", ""))

      if arch != "" {
        return arch
      }
    }

    index += 1
  }

  return host_arch()?
}

proc default_march(arch: Str) [] -> Str {
  if arch == "x86_64" {
    return "-march=x86-64-v3"
  }

  if arch == "aarch64" {
    return "-march=armv8-a"
  }

  return ""
}

proc main(...argv: List[Str]) [fs, process, env, error] {
  let real = p"__REAL__"
  let is_clang = __CLANG__
  let is_cxx = __CXX__

  if ! is_clang {
    env {
      LD_LIBRARY_PATH = f"/usr/lib:/lib:${env.get("LD_LIBRARY_PATH") ?? ""}"
    } {
      run $real @argv ?
    } ?
    return
  }

  let arch = target_arch(argv)?
  let sysroot = sysroot_arg(argv)?
  let frontend = needs_frontend_flags(argv)
  let linking = ! compile_only(argv)
  let runtime = default_runtime(argv)
  let startfiles = default_startfiles(argv)
  var exec_args: List[Str] = [
    "--no-default-config",
    f"--target=${arch}-linux-musl",
    "--sysroot=/",
    "-resource-dir",
    "/usr/lib/llvm22/lib/clang/22",
  ]

  if frontend and ! include_controlled(argv) {
    exec_args = exec_args.push("-nostdinc")

    if is_cxx {
      exec_args = exec_args.extend(["-isystem", "/usr/include/c++/15.2.0"])
      let cxx_target = fp"/usr/include/c++/15.2.0/${arch}-alpine-linux-musl"

      if fs.exists(cxx_target)? {
        exec_args = exec_args.extend(["-isystem", cxx_target.display()])
      }
    }

    exec_args = exec_args.extend(["-isystem", "/usr/lib/llvm22/lib/clang/22/include", "-isystem", "/usr/include"])
  }

  if frontend {
    exec_args = exec_args.push("-fno-stack-protector")
    let march = default_march(arch)

    if march != "" and ! has_option_prefix(argv, "-march=") and ! has_option_prefix(argv, "-mcpu=") {
      exec_args = exec_args.push(march)
    }
  }

  if linking {
    exec_args = exec_args.extend(["-fuse-ld=lld", "-L", "/usr/lib"])

    if runtime {
      exec_args = exec_args.push("-nostdlib")
    }

    if startfiles and ! shared_link(argv) {
      if static_link(argv) {
        exec_args = exec_args.push(rooted(sysroot, "usr/lib/crt1.o")?.display())
      } else {
        exec_args = exec_args.push(rooted(sysroot, "usr/lib/Scrt1.o")?.display())
      }

      exec_args = exec_args.push(rooted(sysroot, "usr/lib/crti.o")?.display())
    }
  }

  exec_args = exec_args.extend(argv)

  if linking and is_cxx and runtime {
    exec_args = exec_args.extend(["-lstdc++", "-lm"])
  }

  if linking and runtime {
    exec_args = exec_args.push("-lc")
  }

  let builtins = rooted(sysroot, f"usr/lib/libclang_rt.builtins-${arch}.a")?

  if linking and runtime and fs.exists(builtins)? {
    exec_args = exec_args.push(builtins.display())
  }

  if linking and startfiles and ! shared_link(argv) {
    exec_args = exec_args.push(rooted(sysroot, "usr/lib/crtn.o")?.display())
  }

  env {
    LD_LIBRARY_PATH = f"/usr/lib:/lib:${env.get("LD_LIBRARY_PATH") ?? ""}"
  } {
    run $real @exec_args ?
  } ?
}

main(@args)?
"""

  return template.replace("__REAL__", real.display()).replace("__CLANG__", bool_literal(clang)).replace("__CXX__", bool_literal(cxx))
}

proc require_env_path(env_name: Str) [env, error] -> Result[Path] {
  let value = (env.get(env_name) ?? "").trim()

  if value == "" {
    return Err(LlvmToolchainError.Failed(f"${env_name} is required"))
  }

  Path.parse(value)?
}

proc write_wrapper(dest: Path, wrapper_name: Str, real: Path, clang: Bool = false, cxx: Bool = false) [fs, error] {
  let path_value = fp"${dest}/usr/bin/${wrapper_name}"
  fs.mkdir(path_value.parent())?
  fs.remove(path_value, missing_ok: true)?
  fs.write(path_value, xsh_wrapper_source(real, clang, cxx))?
  fs.chmod(path_value, 0o755)?
}

proc install_lld_driver(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/usr/lib/llvm-toolchain/bin")?

  for candidate in [fp"${dest}/usr/bin/ld.lld", fp"${dest}/bin/ld.lld", fp"${dest}/usr/lib/llvm22/bin/ld.lld"] {
    if fs.exists(candidate)? {
      fs.rename(candidate, fp"${dest}/usr/lib/llvm-toolchain/bin/ld.lld", overwrite: true)?
      return
    }
  }

  return Err(LlvmToolchainError.Failed("missing ld.lld in Alpine lld22 payload"))
}

proc extract_apk_sources(dest: Path) [fs, error] {
  for source_name in [
    "clang22.tar.gz",
    "clang22-headers.tar.gz",
    "clang22-libs.tar.gz",
    "compiler-rt.tar.gz",
    "lld22-libs.tar.gz",
    "lld22.tar.gz",
    "llvm22-libs.tar.gz",
    "llvm22.tar.gz",
    "llvm22-dev.tar.gz",
    "llvm22-linker-tools.tar.gz",
    "libstdcxx.tar.gz",
    "libstdcxx-dev.tar.gz",
    "libgcc.tar.gz",
    "libffi.tar.gz",
    "zstd-libs.tar.gz",
    "libxml2.tar.gz",
    "xz-libs.tar.gz",
  ] {
    let source = fp"${dest}/${source_name}"

    if ! fs.exists(source)? {
      continue
    }

    for entry in fs.ls(source)? {
      if entry.name.ends_with(".apk") {
        if source_name != "libgcc.tar.gz" {
          for item in archive.tar_list(entry.path)? {
            if item.kind == "symlink" {
              fs.remove(fp"${dest}/${item.path.display()}", missing_ok: true)?
            }
          }

          archive.tar_extract(entry.path, dest, 0, "auto", true)?
        }
      }
    }

    fs.remove(source, missing_ok: true)?
  }
}

proc install_generated_libgcc(dest: Path) [fs, env, error] {
  let arch = pm_util.target_arch()?
  let source = fp"generated-libgcc-${arch}/libgcc_s-${arch}.so.1"
  let target = fp"${dest}/usr/lib/libgcc_s.so.1"
  fs.install(source, target, 0o644, parents: true, overwrite: true)?
}

proc clean_packaging_inputs(dest: Path) [fs, error] {
  fs.remove(fp"${dest}/files", missing_ok: true)?
  fs.remove(fp"${dest}/generated-libgcc-aarch64", missing_ok: true)?
  fs.remove(fp"${dest}/generated-libgcc-x86_64", missing_ok: true)?

  for entry in fs.ls(dest)? {
    if entry.name.starts_with(".SIGN.") or [".PKGINFO", ".DESCRIPTION", ".INSTALL"].contains(entry.name) or entry.name.starts_with(".trigger") {
      fs.remove(entry.path, missing_ok: true)?
    }
  }
}

export proc build(dest: Path) [fs, process, env, error] {
  let _ = fs.copy_tree(p".", dest, parents: true, overwrite: true)?
  extract_apk_sources(dest)?
  install_generated_libgcc(dest)?
  clean_packaging_inputs(dest)?

  for path_value in [fp"${dest}/usr/lib/libz.so.1", fp"${dest}/usr/lib/libz.so.1.3.2"] {
    fs.remove(path_value, missing_ok: true)?
  }

  install_lld_driver(dest)?
  let compiler_rt_lib = fp"${dest}/usr/lib/llvm22/lib/clang/22/lib"

  for entry in fs.ls(compiler_rt_lib)? |> where .kind == "dir" {
    if entry.name.ends_with("-alpine-linux-musl") {
      let alias = entry.name.replace("-alpine-linux-musl", "-linux-musl")
      let alias_path = fp"${compiler_rt_lib}/${alias}"
      fs.remove(alias_path, missing_ok: true)?
      fs.symlink(Path.parse(entry.name)?, alias_path)?
    }
  }

  write_wrapper(dest, "cc", p"/usr/lib/llvm22/bin/clang-22", clang: true)?
  write_wrapper(dest, "clang", p"/usr/lib/llvm22/bin/clang-22", clang: true)?
  write_wrapper(dest, "c++", p"/usr/lib/llvm22/bin/clang++", clang: true, cxx: true)?
  write_wrapper(dest, "clang++", p"/usr/lib/llvm22/bin/clang++", clang: true, cxx: true)?
  write_wrapper(dest, "ld", p"/usr/lib/llvm-toolchain/bin/ld.lld")?
  write_wrapper(dest, "ld.lld", p"/usr/lib/llvm-toolchain/bin/ld.lld")?
  write_wrapper(dest, "ar", p"/usr/bin/llvm22-ar")?
  write_wrapper(dest, "ranlib", p"/usr/bin/llvm22-ranlib")?
  write_wrapper(dest, "nm", p"/usr/bin/llvm22-nm")?
  write_wrapper(dest, "objcopy", p"/usr/bin/llvm22-objcopy")?
  write_wrapper(dest, "objdump", p"/usr/bin/llvm22-objdump")?
  write_wrapper(dest, "readelf", p"/usr/bin/llvm22-readelf")?
  write_wrapper(dest, "strip", p"/usr/bin/llvm22-strip")?

  for tool in ["ar", "ranlib", "nm", "objcopy", "objdump", "readelf", "strip"] {
    write_wrapper(dest, f"llvm-${tool}", fp"/usr/bin/llvm22-${tool}")?
  }
}
