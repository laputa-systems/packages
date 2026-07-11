use pm.util as pm_util

error GnuStubsError = Failed(message: Str)

export let name = "gnu-stubs"

export let ver = "22.1.8"

export let rel = "6"

export let deps = ["musl"]

export let mkdeps = ["llvm-toolchain"]

export let sources = [p"files/.keep"]

export let checksums = [
  "SKIP",
]

export proc build(dest: Path) [fs, process, env, error] {
  let build_arch = pm_util.build_arch()?
  let target_arch = pm_util.target_arch()?

  if build_arch != target_arch {
    return Err(GnuStubsError.Failed("gnu-stubs requires a native build (build_arch == target_arch)"))
  }

  let laputa_root = fp"${env.get("LAPUTA_ROOT") ?? ""}"
  let clang = fp"${laputa_root}/usr/lib/llvm22/bin/clang"
  let libunwind = fp"${laputa_root}/usr/lib/llvm22/lib/libunwind.a"

  if ! fs.exists(clang)? {
    return Err(GnuStubsError.Failed(f"clang not found at ${clang}"))
  }

  if ! fs.exists(libunwind)? {
    return Err(GnuStubsError.Failed(f"libunwind.a not found at ${libunwind}"))
  }

  # Rust's musl target hardcodes -lgcc_s, and the prebuilt cargo binary
  # dynamically links libgcc_s.so.1 for unwinding. The prebuilt LLVM tree
  # does not ship crtbeginS.o, crtendS.o, or libgcc_s.so.
  #
  # crtbeginS.o / crtendS.o: empty object files. The linker accepts them
  # without symbols; they exist only to satisfy Cargo's link line.
  #
  # libgcc_s.so / libgcc_s.so.1: built from the prebuilt tree's own
  # libunwind.a (--whole-archive) so all _Unwind_* symbols are exported.
  # This avoids adding a separate libunwind package dependency while
  # providing the unwinding symbols cargo needs at runtime.
  #
  # Only created for native builds; cross-arch builds skip stub generation
  # since the host compiler can't link target-arch object files.
  let stub_src = fp"${dest}/.stub.c"
  let libdir = fp"${dest}/usr/lib"
  fs.write(stub_src, "")?
  fs.mkdir(libdir.parent)?
  fs.mkdir(libdir)?

  env {
    LD_LIBRARY_PATH = f"${laputa_root}/usr/lib/llvm22/lib:${env.get("LD_LIBRARY_PATH") ?? ""}"
  } {
    run $clang "-target" f"${target_arch}-linux-musl" "-c" $stub_src "-o" fp"${libdir}/crtbeginS.o" ?
    run $clang "-target" f"${target_arch}-linux-musl" "-c" $stub_src "-o" fp"${libdir}/crtendS.o" ?
    fs.remove(stub_src)?
    run $clang "-target" f"${target_arch}-linux-musl" "-shared" "-nostartfiles" "-nostdlib" "-o" fp"${libdir}/libgcc_s.so" "-Wl,--whole-archive" $libunwind "-Wl,--no-whole-archive" ?
  } ?

  fs.symlink(p"libgcc_s.so", fp"${libdir}/libgcc_s.so.1")?
}

export let filetree = [
  {path: p"usr/lib/crtbeginS.o", kind: "binary"},
  {path: p"usr/lib/crtendS.o", kind: "binary"},
  {path: p"usr/lib/libgcc_s.so", kind: "binary"},
  {path: p"usr/lib/libgcc_s.so.1", kind: "symlink"},
]
