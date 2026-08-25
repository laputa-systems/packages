##! Package recipe metadata and build operations.
use pm.util as pm_util

error SudoRsBuildError = MissingRustStd(path: Str)

## Package recipe export.
export let name = "sudo-rs"

## Explicit payload or metapackage classification.
export let package_kind = "payload"

## Package recipe export.
export let ver = "0.2.13"

## Package recipe export.
export let rel = "16"

## Package recipe export.
export let deps = ["linux-pam", "gnu-stubs", "musl"]

## Package recipe export.
export let mkdeps_host = ["cargo", "llvm-toolchain", "linux-pam", "ca-certificates"]

## Package recipe export.
export let upstream_sources = [
  {
    source: p"https://static.crates.io/crates/sudo-rs/sudo-rs-VERSION.crate",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "aarch64",
        sha256: "3537fb3bdef870cacb354892e3fc76af7775e691570d49b402295c8fbef3656b",
      },
      {
        arch: "x86_64",
        sha256: "3537fb3bdef870cacb354892e3fc76af7775e691570d49b402295c8fbef3656b",
      },
    ],
  },
  {
    source: p"https://static.rust-lang.org/dist/2026-04-16/rust-std-1.95.0-ARCH-unknown-linux-musl.tar.xz => rust-std",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "aarch64",
        sha256: "f6710416ed9a7d5cf2a15efa761eb79a1deeb43f9961bbe05cc97bec4ef9064a",
      },
      {
        arch: "x86_64",
        sha256: "aee540abf132920f791ef781489851a078d69dff493fb628d49c1d573f92bb3a",
      },
    ],
  },
]

## Package recipe export.
export let filetree = [
  {
    path: p"usr/bin/su",
    kind: "binary",
  },
  {
    path: p"usr/bin/sudo",
    kind: "binary",
  },
  {
    path: p"usr/bin/sudoedit",
    kind: "symlink",
  },
]

pure rust_triple(arch: Str) -> Str {
  if arch == "aarch64" or arch == "arm64" {
    return "aarch64-unknown-linux-musl"
  }

  if arch == "amd64" {
    return "x86_64-unknown-linux-musl"
  }

  return f"${arch}-unknown-linux-musl"
}

proc stage_rustlib(source: Path, dest: Path) [fs, error] {
  fs.remove(dest, missing_ok: true)?
  fs.mkdir(dest)?

  for entry in fs.walk(source, gitignore: false)? |> sort-by .path {
    continue when entry.path == source
    let relative = entry.path.relative_to(source)
    let out = fp"${dest}/${relative}"

    if entry.kind == "dir" {
      fs.mkdir(out)?
    } else if entry.kind == "file" {
      let mode = if entry.path.executable()? { 0o755 } else { 0o644 }
      fs.install(entry.path, out, mode, parents: true, overwrite: true)?
    } else if entry.kind == "symlink" {
      fs.mkdir(out.parent)?
      fs.remove(out, missing_ok: true)?
      fs.symlink(entry.path.readlink()?, out)?
    }
  }
}

## Package recipe export.
export proc build(dest: Path) [fs, process, env, error] {
  let cargo = process.which("cargo")?
  let cc = process.which("cc")?
  let target_arch = pm_util.target_arch()?
  let build_root = fp"${env.get("XSH_PM_BUILD_ROOT") ?? ""}"
  let target_root_value = (env.get("LAPUTA_ROOT") ?? env.get("XSH_PM_ROOT") ?? "").trim()
  let target_root = if target_root_value != "" { fp"${target_root_value}" } else { cc.parent.parent }
  var libdir = fp"${target_root}/usr/lib"

  if ! fs.exists(libdir)? {
    libdir = fp"${cc.parent.parent}/lib"
  }

  let build_arch = pm_util.build_arch()?
  let triple = rust_triple(target_arch)
  let host_triple = rust_triple(build_arch)
  let host_cc = if fs.exists(fp"${build_root}/usr/bin/cc")? { fp"${build_root}/usr/bin/cc" } else { cc }
  let host_libdir = fp"${build_root}/usr/lib"
  let target_rustlib = fp"rust-std/rust-std-${triple}/lib/rustlib/${triple}"
  let staged_rustlib = fp"${target_root}/usr/lib/rustlib/${triple}"

  if ! fs.exists(fp"${staged_rustlib}/lib")? {
    if ! fs.exists(target_rustlib)? {
      return Err(SudoRsBuildError.MissingRustStd(target_rustlib.display()))
    }

    stage_rustlib(target_rustlib, staged_rustlib)?
  }

  let target_rustflags = f"-C panic=abort -C target-feature=-crt-static -C linker=${cc.display()} -L native=${libdir.display()} -C link-arg=-Wl,--as-needed -C link-arg=-Wl,-rpath,/usr/lib"
  let host_rustflags = f"-C panic=abort -C target-feature=-crt-static -C linker=${host_cc.display()} -L native=${host_libdir.display()} -C link-arg=-Wl,--as-needed"
  let aarch64_rustflags = if triple == "aarch64-unknown-linux-musl" { target_rustflags } else { host_rustflags }

  let x86_64_rustflags = if host_triple == "x86_64-unknown-linux-musl" and triple != host_triple {
    host_rustflags
  } else {
    target_rustflags
  }

  let aarch64_linker = if triple == "aarch64-unknown-linux-musl" { cc.display() } else { host_cc.display() }
  let x86_64_linker = if triple == "x86_64-unknown-linux-musl" { cc.display() } else { host_cc.display() }
  let current_path = env.get("PATH") ?? ""
  let cargo_path = f"${host_cc.parent.display()}:${current_path}"

  env {
    PATH = cargo_path
    CC = host_cc.display()
    HOST_CC = host_cc.display()
    CARGO_HOME = fp"${fs.cwd()?}/.cargo-home".display()
    CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER = aarch64_linker
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER = x86_64_linker
    CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_RUSTFLAGS = aarch64_rustflags
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_RUSTFLAGS = x86_64_rustflags
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt"
  } {
    run $cargo build "--release" "--target" $triple "--bin" "sudo" "--bin" "su" ?
  } ?

  fs.install(fp"target/${triple}/release/sudo", fp"${dest}/usr/bin/sudo", 0o4755, parents: true, overwrite: true)?
  fs.install(fp"target/${triple}/release/su", fp"${dest}/usr/bin/su", 0o4755, parents: true, overwrite: true)?
  fs.symlink(p"sudo", fp"${dest}/usr/bin/sudoedit")?
}
