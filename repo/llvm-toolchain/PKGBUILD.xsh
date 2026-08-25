##! LLVM toolchain package definition and build operations.
use pm.util as pm_util

error LlvmToolchainError = Failed(message: Str)

## Package name.
export let name = "llvm-toolchain"

## Upstream LLVM version.
export let ver = "23.1.0-rc2"

## Package release revision.
export let rel = "13"

## Runtime package dependencies.
export let deps = ["musl"]

## Host-side build dependencies.
export let mkdeps_host = []

## Preserve upstream binaries without stripping.
export let nostrip = true

## Upstream source archives and checksums.
export let upstream_sources = [
  {
    source: p"https://github.com/laputa-systems/llvm-prebuilt-musl/releases/download/llvm-musl-VERSION-6eb5fb9/clang+llvm-VERSION-ARCH-linux-musl.tar.xz => llvm-prebuilt",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "aarch64",
        sha256: "0c9bd6f0fefa26dbdb7d6ed568f3799b558428b1ce1264656aa328fc6fd9e32d",
      },
      {
        arch: "x86_64",
        sha256: "36647cca0bf57d206a6ce757d07a9d8489ef6ccf283a2cc7f740d1cba99a088b",
      },
    ],
  },
]

## Installed package file tree.
export let filetree = [
  {
    path: p"usr",
    kind: "tree",
  },
  {
    path: p"usr/lib/llvm23/bin/clang",
    kind: "symlink",
  },
  {
    path: p"usr/lib/llvm23/bin/clang++",
    kind: "symlink",
  },
  {
    path: p"usr/lib/llvm23/bin/clang-23",
    kind: "binary",
  },
  {
    path: p"usr/lib/llvm23/bin/clang-cl",
    kind: "symlink",
  },
  {
    path: p"usr/lib/llvm23/bin/clang-cpp",
    kind: "symlink",
  },
  {
    path: p"usr/lib/llvm23/bin/ld.lld",
    kind: "symlink",
  },
  {
    path: p"usr/lib/llvm23/bin/ld64.lld",
    kind: "symlink",
  },
  {
    path: p"usr/lib/llvm23/bin/lld",
    kind: "binary",
  },
  {
    path: p"usr/lib/llvm23/bin/lld-link",
    kind: "symlink",
  },
  {
    path: p"usr/lib/llvm23/bin/llvm-ar",
    kind: "binary",
  },
  {
    path: p"usr/lib/llvm23/bin/llvm-nm",
    kind: "binary",
  },
  {
    path: p"usr/lib/llvm23/bin/llvm-objcopy",
    kind: "binary",
  },
  {
    path: p"usr/lib/llvm23/bin/llvm-objdump",
    kind: "binary",
  },
  {
    path: p"usr/lib/llvm23/bin/llvm-ranlib",
    kind: "symlink",
  },
  {
    path: p"usr/lib/llvm23/bin/llvm-readelf",
    kind: "symlink",
  },
  {
    path: p"usr/lib/llvm23/bin/llvm-readobj",
    kind: "binary",
  },
  {
    path: p"usr/lib/llvm23/bin/llvm-size",
    kind: "binary",
  },
  {
    path: p"usr/lib/llvm23/bin/llvm-strings",
    kind: "binary",
  },
  {
    path: p"usr/lib/llvm23/bin/llvm-strip",
    kind: "symlink",
  },
  {
    path: p"usr/lib/llvm23/bin/llvm-symbolizer",
    kind: "binary",
  },
  {
    path: p"usr/lib/llvm23/bin/wasm-ld",
    kind: "symlink",
  },
  {
    path: p"usr/lib/llvm23/lib/libLTO.so",
    kind: "symlink",
  },
  {
    path: p"usr/lib/llvm23/lib/libLTO.so.23.1-rc2",
    kind: "binary",
  },
  {
    path: p"usr/lib/llvm23/lib/libclang.so",
    kind: "symlink",
  },
  {
    path: p"usr/lib/llvm23/lib/libclang.so.23.1-rc2",
    kind: "symlink",
  },
  {
    path: p"usr/lib/llvm23/lib/libclang.so.23.1.0-rc2",
    kind: "binary",
  },
]

pure bool_literal(value: Bool) -> Str {
  if value {
    return "true"
  }

  return "false"
}

pure xsh_wrapper_source(real: Path, clang: Bool, cxx: Bool) -> Str {
  let template = """#!/bin/xsh
proc has_option_prefix(argv: List[Str], prefix: Str) [] -> Bool {
  for arg in argv {
    if arg.starts_with(prefix) {
      return true
    }
  }

  return false
}

proc compile_only(argv: List[Str]) [] -> Bool {
  return "-c" in argv or "-S" in argv or "-E" in argv
}

proc shared_link(argv: List[Str]) [] -> Bool {
  return "-shared" in argv
}

proc static_link(argv: List[Str]) [] -> Bool {
  return "-static" in argv
}

proc default_runtime(argv: List[Str]) [] -> Bool {
  return "-nostdlib" not in argv and "-nodefaultlibs" not in argv
}

proc default_startfiles(argv: List[Str]) [] -> Bool {
  return default_runtime(argv) and "-nostartfiles" not in argv
}

proc include_controlled(argv: List[Str]) [] -> Bool {
  return "-nostdinc" in argv or "-nostdlibinc" in argv or "-nostdsysteminc" in argv
}

proc sysroot_arg(argv: List[Str]) [error] -> Result[Path] {
  var index = 0

  while index < argv.len() {
    let arg = argv[index]

    if arg == "--sysroot" and index + 1 < argv.len() {
      return Path(argv[index + 1])
    }

    if arg.starts_with("--sysroot=") {
      return Path(arg.replace("--sysroot=", ""))
    }

    index += 1
  }

  return p"/"
}

proc rooted(root: Path, rel: Str) [] -> Path {
  if root.display() == "/" {
    return fp"/\${rel}"
  }

  fp"\${root}/\${rel}"
}

proc source_like(arg: Str) [] -> Bool {
  return arg.ends_with(".c") or arg.ends_with(".cc") or arg.ends_with(".cpp") or arg.ends_with(".cxx") or arg.ends_with(".C") or arg.ends_with(".S")
}

proc needs_frontend_flags(argv: List[Str]) [] -> Bool {
  if "-E" in argv {
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
      if arg in ["-o", "-MF", "-MT", "-MQ", "-include", "-isystem"] and index + 1 < argv.len() {
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
      LD_LIBRARY_PATH = f"/usr/lib:/usr/lib/llvm23/lib:/lib:\${env.get("LD_LIBRARY_PATH") ?? ""}"
    } {
      run \$real @argv ?
    } ?
    return
  }

  let arch = target_arch(argv)?
  let sysroot = sysroot_arg(argv)?
  let frontend = needs_frontend_flags(argv)
  let linking = ! compile_only(argv)
  let runtime = default_runtime(argv)
  let startfiles = default_startfiles(argv)
  var exec_args = [
    "--no-default-config",
    f"--target=\${arch}-linux-musl",
    "--sysroot=/",
    "-resource-dir",
    "/usr/lib/llvm23/lib/clang/23",
  ]

  if frontend and ! include_controlled(argv) {
    exec_args = exec_args.push("-nostdinc")

    if is_cxx {
      exec_args = exec_args.extend(["-isystem", "/usr/lib/llvm23/include/c++/v1"])
      let cxx_target = fp"/usr/lib/llvm23/include/\${arch}-linux-musl/c++/v1"

      if fs.exists(cxx_target)? {
        exec_args = exec_args.extend(["-isystem", cxx_target.display()])
      }
    }

    exec_args = exec_args.extend(["-isystem", "/usr/lib/llvm23/lib/clang/23/include", "-isystem", "/usr/include"])
  }

  if frontend {
    exec_args = exec_args.push("-fno-stack-protector")
    let march = default_march(arch)

    if march != "" and ! has_option_prefix(argv, "-march=") and ! has_option_prefix(argv, "-mcpu=") {
      exec_args = exec_args.push(march)
    }
  }

  if linking {
    exec_args = exec_args.extend([
      "-fuse-ld=lld",
      "-L",
      rooted(sysroot, "usr/lib").display(),
      "-L",
      rooted(sysroot, "usr/lib/llvm23/lib").display(),
    ])

    if runtime {
      exec_args = exec_args.push("-nostdlib")
    }

    if startfiles and ! shared_link(argv) {
      if static_link(argv) {
        exec_args = exec_args.push(rooted(sysroot, "usr/lib/crt1.o").display())
      } else {
        exec_args = exec_args.push(rooted(sysroot, "usr/lib/Scrt1.o").display())
      }

      exec_args = exec_args.push(rooted(sysroot, "usr/lib/crti.o").display())
    }
  }

  exec_args = exec_args.extend(argv)

  if linking and is_cxx and runtime {
    exec_args = exec_args.extend(["-lc++", "-lc++abi"])
    let unwind = rooted(sysroot, "usr/lib/llvm23/lib/libunwind.a")

    if fs.exists(unwind)? {
      exec_args = exec_args.push(unwind.display())
    }

    exec_args = exec_args.push("-lm")
  }

  if linking and runtime {
    exec_args = exec_args.push("-lc")
  }

  let builtins = rooted(sysroot, f"usr/lib/llvm23/lib/clang/23/lib/linux/libclang_rt.builtins-\${arch}.a")

  if linking and runtime and fs.exists(builtins)? {
    exec_args = exec_args.push(builtins.display())
  }

  if linking and startfiles and ! shared_link(argv) {
    exec_args = exec_args.push(rooted(sysroot, "usr/lib/crtn.o").display())
  }

  env {
    LD_LIBRARY_PATH = f"/usr/lib:/usr/lib/llvm23/lib:/lib:\${env.get("LD_LIBRARY_PATH") ?? ""}"
  } {
    run \$real @exec_args ?
  } ?
}

main(@args)?
"""

  return template.replace("__REAL__", real.display())
    .replace("__CLANG__", bool_literal(clang))
    .replace(
      "__CXX__",
      bool_literal(
        cxx,
      ),
    )
}

proc write_wrapper(dest: Path, wrapper_name: Str, real: Path, clang: Bool = false, cxx: Bool = false) [fs, error] {
  let path_value = fp"${dest}/usr/bin/${wrapper_name}"
  fs.mkdir(path_value.parent())?
  fs.remove(path_value, missing_ok: true)?
  fs.write(path_value, xsh_wrapper_source(real, clang, cxx))?
  fs.chmod(path_value, 0o755)?
}

proc require_file(path_value: Path, label: Str) [fs, error] {
  if ! fs.exists(path_value)? {
    return Err(LlvmToolchainError.Failed(f"missing ${label}: ${path_value.display()}"))
  }
}

proc require_executable(path_value: Path, label: Str) [fs, error] {
  require_file(path_value, label)?
  let meta = fs.metadata(path_value)?

  if meta.mode % 0o1000 == 0 {
    return Err(LlvmToolchainError.Failed(f"${label} is not executable: ${path_value.display()}"))
  }
}

proc install_tool_alias(bin: Path, tool_name: Str, target: Str) [fs, error] {
  let link = fp"${bin}/${tool_name}"

  if fs.exists(link)? {
    return
  }

  require_file(fp"${bin}/${target}", target)?
  fs.symlink(fp"${target}", link)?
}

proc install_prebuilt_tree(dest: Path) [fs, env, error] {
  let arch = pm_util.target_arch()?
  let source = p"llvm-prebuilt"
  let target = fp"${dest}/usr/lib/llvm23"

  if ! fs.exists(source)? {
    return Err(LlvmToolchainError.Failed("missing staged LLVM prebuilt tree"))
  }

  fs.remove(target, missing_ok: true)?
  let _ = fs.copy_tree(source, target, parents: true, overwrite: true)?
  let bin = fp"${target}/bin"
  install_tool_alias(bin, "clang-23", "clang")?
  install_tool_alias(bin, "clang++", "clang")?
  install_tool_alias(bin, "ld.lld", "lld")?
  install_tool_alias(bin, "llvm-readelf", "llvm-readobj")?

  for tool in [
    "clang",
    "clang++",
    "ld.lld",
    "llvm-ar",
    "llvm-ranlib",
    "llvm-nm",
    "llvm-objcopy",
    "llvm-objdump",
    "llvm-readelf",
    "llvm-strip",
  ] {
    require_executable(fp"${bin}/${tool}", tool)?
  }

  require_file(fp"${target}/lib/clang/23/include/stddef.h", "Clang resource headers")?
  require_file(fp"${target}/lib/clang/23/lib/linux/libclang_rt.builtins-${arch}.a", "compiler-rt builtins")?
}

## Install target-specific compiler wrapper links.
export proc install_wrappers(dest: Path) [fs, error] {
  write_wrapper(dest, "cc", /usr/lib/llvm23/bin/clang, clang: true)?
  write_wrapper(dest, "clang", /usr/lib/llvm23/bin/clang, clang: true)?
  write_wrapper(dest, "c++", /usr/lib/llvm23/bin/clang++, clang: true, cxx: true)?
  write_wrapper(dest, "clang++", /usr/lib/llvm23/bin/clang++, clang: true, cxx: true)?
  write_wrapper(dest, "ld", /usr/lib/llvm23/bin/ld.lld)?
  write_wrapper(dest, "ld.lld", /usr/lib/llvm23/bin/ld.lld)?
  write_wrapper(dest, "ar", /usr/lib/llvm23/bin/llvm-ar)?
  write_wrapper(dest, "ranlib", /usr/lib/llvm23/bin/llvm-ranlib)?
  write_wrapper(dest, "nm", /usr/lib/llvm23/bin/llvm-nm)?
  write_wrapper(dest, "objcopy", /usr/lib/llvm23/bin/llvm-objcopy)?
  write_wrapper(dest, "objdump", /usr/lib/llvm23/bin/llvm-objdump)?
  write_wrapper(dest, "readelf", /usr/lib/llvm23/bin/llvm-readelf)?
  write_wrapper(dest, "strip", /usr/lib/llvm23/bin/llvm-strip)?

  for tool in ["ar", "ranlib", "nm", "objcopy", "objdump", "readelf", "strip"] {
    write_wrapper(dest, f"llvm-${tool}", fp"/usr/lib/llvm23/bin/llvm-${tool}")?
  }
}

## Build and install the LLVM toolchain package.
export proc build(dest: Path) [fs, process, env, error] {
  install_prebuilt_tree(dest)?
  install_wrappers(dest)?
}
