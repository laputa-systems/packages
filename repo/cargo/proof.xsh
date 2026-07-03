use pm.proof as proof
use pm.util as pm_util

proc main(rootfs: Path = /rootfs) [fs, process, env, error] {
  proof.target_elf(rootfs, p"usr/bin/cargo", "cargo")?
  proof.target_elf(rootfs, p"usr/bin/rustc", "rustc")?
  let target_arch = pm_util.target_arch()?
  let rust_triple = if target_arch == "aarch64" { "aarch64-unknown-linux-musl" } else { "x86_64-unknown-linux-musl" }

  if ! fs.exists(fp"${rootfs}/usr/lib64/rustlib/${rust_triple}/lib")? {
    return Err(proof.ProofError.Failed("proof-cargo", f"missing rust std for ${rust_triple}"))
  }

  if pm_util.build_arch()? != target_arch {
    print "cargo ok: cross-built "${target_arch}
    return
  }

  let dynlinker = fp"${rootfs}/usr/lib/ld-musl-${target_arch}.so.1"
  let gcc_s = fp"${rootfs}/usr/lib/libgcc_s.so.1"

  if ! fs.exists(gcc_s)? {
    print "cargo ok: (runtime test skipped — libgcc_s.so.1 not in root)"
    return
  }

  var cargo = ""
  var rustc = ""

  env {
    LD_LIBRARY_PATH = fp"${rootfs}/usr/lib".display()
  } {
    cargo = run.text $dynlinker fp"${rootfs}/usr/bin/cargo" "--version" ?
    rustc = run.text $dynlinker fp"${rootfs}/usr/bin/rustc" "--version" ?
  } ?

  if ! cargo.starts_with("cargo ") {
    return Err(proof.ProofError.Failed("proof-cargo", f"unexpected cargo version: ${cargo.trim()}"))
  }

  if ! rustc.starts_with("rustc ") {
    return Err(proof.ProofError.Failed("proof-cargo", f"unexpected rustc version: ${rustc.trim()}"))
  }

  print "cargo ok"
}

main(@args)?
