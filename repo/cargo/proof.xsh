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
    print "cargo ok: (runtime test skipped \u{2014} libgcc_s.so.1 not in root)"
    return
  }

  var cargo = ""
  var rustc = ""
  let tmp = fp"${rootfs}/var/tmp/proof-cargo"
  fs.remove(tmp, missing_ok: true)?
  fs.mkdir(tmp)?
  defer fs.remove(tmp, missing_ok: true)?

  fs.mkdir(fp"${tmp}/src")?
  fs.mkdir(fp"${tmp}/cargo-home")?
  fs.write(
    fp"${tmp}/Cargo.toml",
    """[package]
name = "cargo-proof-hello"
version = "0.1.0"
edition = "2024"
""",
  )?
  fs.write(
    fp"${tmp}/src/main.rs",
    """fn main() {
    println!("hello cargo");
}
""",
  )?

  let rustc_wrapper = fp"${tmp}/rustc-wrapper"
  fs.write(
    rustc_wrapper,
    f"""#!/bin/xsh
proc main(...args: List[Str]) [process, error] {
  run fp"${dynlinker.display()}" fp"${rootfs}/usr/bin/rustc" @args ?
}
main(@args)?
""",
  )?
  fs.chmod(rustc_wrapper, 0o755)?

  let linker_wrapper = fp"${tmp}/linker-wrapper"
  let linker = fp"${rootfs}/usr/lib/llvm23/bin/ld.lld"
  fs.write(
    linker_wrapper,
    f"""#!/bin/xsh
proc main(...args: List[Str]) [process, error] {
  var linker_args: List[Str] = []
  for arg in args {
    if arg.starts_with("-Wl,") {
      let options = arg.split(",")
      var index = 1
      while index < options.len() {
        linker_args = linker_args.push(options[index])
        index += 1
      }
    } else if arg != "-nostartfiles" and arg != "-nodefaultlibs" {
      linker_args = linker_args.push(arg)
    }
  }
  run fp"${dynlinker.display()}" fp"${linker.display()}" @linker_args ?
}
main(@args)?
""",
  )?
  fs.chmod(linker_wrapper, 0o755)?

  env {
    LD_LIBRARY_PATH = fp"${rootfs}/usr/lib".display()
    PATH = f"${rootfs}/usr/bin:${env.get("PATH") ?? ""}"
    CARGO_HOME = fp"${tmp}/cargo-home".display()
    RUSTC = rustc_wrapper.display()
    RUSTFLAGS = f"-L native=${rootfs}/usr/lib -C linker=${linker_wrapper.display()}"
  } {
    cargo = run.text $dynlinker fp"${rootfs}/usr/bin/cargo" "--version" ?
    rustc = run.text $dynlinker fp"${rootfs}/usr/bin/rustc" "--version" ?
    run $dynlinker fp"${rootfs}/usr/bin/cargo" "build" "--release" "--offline" "--target" $rust_triple "--manifest-path" fp"${tmp}/Cargo.toml" ?
  } ?

  if ! cargo.starts_with("cargo ") {
    return Err(proof.ProofError.Failed("proof-cargo", f"unexpected cargo version: ${cargo.trim()}"))
  }

  if ! rustc.starts_with("rustc ") {
    return Err(proof.ProofError.Failed("proof-cargo", f"unexpected rustc version: ${rustc.trim()}"))
  }

  let hello = fp"${tmp}/target/${rust_triple}/release/cargo-proof-hello"
  let out = run.text $hello ?
  let trimmed = out.trim()

  if trimmed != "hello cargo" {
    return Err(proof.ProofError.Failed("proof-cargo", f"unexpected hello output: ${trimmed}"))
  }

  print "cargo ok: "${trimmed}
}

main(@args)?
