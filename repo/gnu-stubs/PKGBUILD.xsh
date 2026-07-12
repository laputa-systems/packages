use pm.util as pm_util

error GnuStubsError = Failed(message: Str)

export let name = "gnu-stubs"

export let ver = "22.1.8"

export let rel = "29"

export let deps = ["musl"]

export let mkdeps_host = ["llvm-toolchain"]

export let upstream_sources = [
  {source: p"files/.keep", kind: "auto", architectures: ["all"], checksums: [{arch: "all", sha256: "SKIP"}]},
]

export let filetree = [
  {path: p"usr/lib/crtbeginS.o", kind: "binary"},
  {path: p"usr/lib/crtendS.o", kind: "binary"},
  {path: p"usr/lib/libgcc_s.so", kind: "binary"},
  {path: p"usr/lib/libgcc_s.so.1", kind: "symlink"},
]

export proc build(dest: Path) [fs, process, env, error] {
  let build_arch = pm_util.build_arch()?
  let target_arch = pm_util.target_arch()?

  if build_arch != target_arch or (target_arch != "aarch64" and target_arch != "x86_64") {
    return Err(GnuStubsError.Failed("gnu-stubs requires a native aarch64 or x86_64 build"))
  }

  let laputa_root = fp"${env.get("LAPUTA_ROOT") ?? ""}"
  let clang = fp"${laputa_root}/usr/lib/llvm22/bin/clang"
  let lld = fp"${laputa_root}/usr/lib/llvm22/bin/ld.lld"
  let llvm_ar = fp"${laputa_root}/usr/lib/llvm22/bin/llvm-ar"
  let llvm_objcopy = fp"${laputa_root}/usr/lib/llvm22/bin/llvm-objcopy"
  let libunwind = fp"${laputa_root}/usr/lib/llvm22/lib/libunwind.a"
  let builtins = fp"${laputa_root}/usr/lib/llvm22/lib/clang/22/lib/linux/libclang_rt.builtins-${target_arch}.a"

  # Rust's musl target hardcodes -lgcc_s, and the prebuilt cargo binary
  # dynamically links libgcc_s.so.1 for unwinding. The prebuilt LLVM tree
  # does not ship crtbeginS.o, crtendS.o, or libgcc_s.so.
  #
  # crtbeginS.o / crtendS.o: empty object files. The linker accepts them
  # without symbols; they exist only to satisfy Cargo's link line.
  #
  # libgcc_s.so / libgcc_s.so.1: built from libunwind.a and the compiler-rt
  # objects that provide the helpers required by the dynamically loaded
  # rust-lld. Compiler-rt marks those helpers hidden, so make only these
  # required symbols default-visible before linking the shared object.
  let stub_src = fp"${dest}/.stub.c"
  let builtins_dir = fp"${dest}/.builtins"
  let visibility_map = fp"${dest}/.libgcc.visibility"
  let export_map = fp"${dest}/.libgcc.exports"
  let libdir = fp"${dest}/usr/lib"
  let libgcc = fp"${libdir}/libgcc_s.so"
  let comparetf2 = fp"${builtins_dir}/comparetf2.c.o"
  let divtf3 = fp"${builtins_dir}/divtf3.c.o"
  let extendsftf2 = fp"${builtins_dir}/extendsftf2.c.o"
  let floatsitf = fp"${builtins_dir}/floatsitf.c.o"
  let floatunditf = fp"${builtins_dir}/floatunditf.c.o"
  let multf3 = fp"${builtins_dir}/multf3.c.o"
  let trunctfdf2 = fp"${builtins_dir}/trunctfdf2.c.o"
  let clear_cache = fp"${builtins_dir}/clear_cache.c.o"
  fs.write(stub_src, "")?
  fs.write(visibility_map, """__floatunditf
__divtf3
__clear_cache
__unordtf2
__extendsftf2
__trunctfdf2
__getf2
__multf3
__letf2
__floatsitf
__gttf2
""")?
  fs.write(export_map, """{
  global:
    *;
};
""")?
  fs.mkdir(libdir.parent)?
  fs.mkdir(libdir)?
  fs.mkdir(builtins_dir)?

  env {
    LD_LIBRARY_PATH = f"${laputa_root}/usr/lib/llvm22/lib:${env.get("LD_LIBRARY_PATH") ?? ""}"
  } {
    run $clang "-target" f"${target_arch}-linux-musl" "-c" $stub_src "-o" fp"${libdir}/crtbeginS.o" ?
    run $clang "-target" f"${target_arch}-linux-musl" "-c" $stub_src "-o" fp"${libdir}/crtendS.o" ?
    cd builtins_dir {
      run $llvm_ar "x" $builtins "comparetf2.c.o" "divtf3.c.o" "extendsftf2.c.o" "floatsitf.c.o" "floatunditf.c.o" "multf3.c.o" "trunctfdf2.c.o" "clear_cache.c.o" ?
    }
    for object in [comparetf2, divtf3, extendsftf2, floatsitf, floatunditf, multf3, trunctfdf2, clear_cache] {
      let visible = fp"${object.display()}.visible"
      run $llvm_objcopy f"--set-symbols-visibility=${visibility_map.display()}=default" $object $visible ?
      fs.rename(visible, object, overwrite: true)?
    }
    fs.remove(stub_src)?
    run $lld "-shared" "-o" $libgcc "-L" fp"${laputa_root}/usr/lib" "-ldl" "-lpthread" f"--version-script=${export_map.display()}" "--no-gc-sections" "-u" "__floatunditf" "-u" "__divtf3" "-u" "__clear_cache" "-u" "__unordtf2" "-u" "__extendsftf2" "-u" "__trunctfdf2" "-u" "__getf2" "-u" "__multf3" "-u" "__letf2" "-u" "__floatsitf" "-u" "__gttf2" "--whole-archive" $libunwind "--no-whole-archive" $comparetf2 $divtf3 $extendsftf2 $floatsitf $floatunditf $multf3 $trunctfdf2 $clear_cache ?
  } ?

  fs.remove(builtins_dir)?
  fs.remove(visibility_map)?
  fs.remove(export_map)?
  fs.symlink(p"libgcc_s.so", fp"${libdir}/libgcc_s.so.1")?
}
