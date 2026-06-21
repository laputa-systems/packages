use pm.util as pm_util

export let name: Str = "cargo"

export let ver: Str = "1.95.0"

export let rel: Str = "4"

export let deps: List[Str] = ["musl", "llvm-toolchain"]

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://static.rust-lang.org/dist/2026-04-16/cargo-VERSION-ARCH-unknown-linux-musl.tar.xz => cargo",
  p"https://static.rust-lang.org/dist/2026-04-16/rustc-VERSION-ARCH-unknown-linux-musl.tar.xz => rustc",
  p"https://static.rust-lang.org/dist/2026-04-16/rust-std-VERSION-ARCH-unknown-linux-musl.tar.xz => rust-std",
]

export let checksums: List[Str] = ["SKIP", "SKIP", "SKIP"]

export let checksums_aarch64: List[Str] = [
  "3ea32cd155faeefa3f7689d74a9e515641be5163cba1b331099943b79d8680d9",
  "8d05ce001477dec7cfee8e778e15883a9b3a73a061d63e491f08429c3c2a5235",
  "f6710416ed9a7d5cf2a15efa761eb79a1deeb43f9961bbe05cc97bec4ef9064a",
]

export let checksums_x86_64: List[Str] = [
  "6abadb9c6f9113f20858a67cfb48c4065c614cb038f543e19d5bf5d768663841",
  "1a18aabec47fd0ada35f82a8864d6319471cbc7cdf7e84e53fed1941018af92d",
  "aee540abf132920f791ef781489851a078d69dff493fb628d49c1d573f92bb3a",
]

export let nostrip: Bool = true

pure rust_dist_arch(arch: Str) -> Str {
  if arch == "arm64" {
    return "aarch64"
  }

  if arch == "amd64" {
    return "x86_64"
  }

  arch
}

export proc build(dest: Path) [fs, env, error] {
  let arch = rust_dist_arch(pm_util.target_arch()?)
  var cargo_src = p"cargo/cargo"
  var rustc_src = p"rustc/rustc"
  var rust_std_src = fp"rust-std/rust-std-${arch}-unknown-linux-musl"

  if ! fs.exists(cargo_src)? {
    cargo_src = fp"cargo/cargo-${ver}-${arch}-unknown-linux-musl/cargo"
  }

  if ! fs.exists(rustc_src)? {
    rustc_src = fp"rustc/rustc-${ver}-${arch}-unknown-linux-musl/rustc"
  }

  if ! fs.exists(rust_std_src)? {
    rust_std_src = fp"rust-std/rust-std-${ver}-${arch}-unknown-linux-musl/rust-std-${arch}-unknown-linux-musl"
  }

  var copied = fs.copy_tree(cargo_src, fp"${dest}/usr", parents: true, overwrite: true)?
  copied = fs.copy_tree(rustc_src, fp"${dest}/usr", parents: true, overwrite: true)?
  copied = fs.copy_tree(rust_std_src, fp"${dest}/usr", parents: true, overwrite: true)?
  let _ = copied
}
