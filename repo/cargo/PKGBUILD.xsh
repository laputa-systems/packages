##! XSH module `PKGBUILD` package and build operations.
use pm.util as pm_util

## Exported declaration `name`.
export let name = "cargo"

## Exported declaration `ver`.
export let ver = "1.95.0"

## Exported declaration `rel`.
export let rel = "10"

## Exported declaration `deps`.
export let deps = ["musl", "llvm-toolchain", "gnu-stubs"]

## Exported declaration `mkdeps_host`.
export let mkdeps_host = []

## Exported declaration `upstream_sources`.
export let upstream_sources = [
  {
    source: p"https://static.rust-lang.org/dist/2026-04-16/cargo-VERSION-ARCH-unknown-linux-musl.tar.xz => cargo",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "aarch64",
        sha256: "3ea32cd155faeefa3f7689d74a9e515641be5163cba1b331099943b79d8680d9",
      },
      {
        arch: "x86_64",
        sha256: "6abadb9c6f9113f20858a67cfb48c4065c614cb038f543e19d5bf5d768663841",
      },
    ],
  },
  {
    source: p"https://static.rust-lang.org/dist/2026-04-16/rustc-VERSION-ARCH-unknown-linux-musl.tar.xz => rustc",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "aarch64",
        sha256: "8d05ce001477dec7cfee8e778e15883a9b3a73a061d63e491f08429c3c2a5235",
      },
      {
        arch: "x86_64",
        sha256: "1a18aabec47fd0ada35f82a8864d6319471cbc7cdf7e84e53fed1941018af92d",
      },
    ],
  },
  {
    source: p"https://static.rust-lang.org/dist/2026-04-16/rust-std-VERSION-ARCH-unknown-linux-musl.tar.xz => rust-std",
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

## Exported declaration `nostrip`.
export let nostrip = true

let filetree_common = [
  {
    path: p"usr",
    kind: "tree",
  },
  {
    path: p"usr/bin/cargo",
    kind: "binary",
  },
  {
    path: p"usr/bin/rustc",
    kind: "binary",
  },
  {
    path: p"usr/bin/rustdoc",
    kind: "binary",
  },
  {
    path: p"usr/libexec/rust-analyzer-proc-macro-srv",
    kind: "binary",
  },
]

## Exported declaration `filetree_aarch64`.
export let filetree_aarch64 = filetree_common.extend(
  [
    {
      path: p"usr/lib/libdarling_macro-619e2eaae5e494e6.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/libderive_setters-996d50759f1136d8.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/libderive_where-545b197fc70d0275.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/libdisplaydoc-630fca802ee793c9.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/libproc_macro_hack-e91a45232ab3e1c3.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/libref_cast_impl-dae3b74ea09f2c81.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/librustc_driver-e898dbc1cb8012ad.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/librustc_index_macros-89604c5bb2a94459.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/librustc_macros-b193518b75be0209.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/librustc_type_ir_macros-b32bc89b2b787f4f.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/libschemars_derive-1494bf2abbce938f.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/libserde_derive-2955a7119b2522f4.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/libthiserror_impl-88a89f42cbfb00c1.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/libtracing_attributes-f9ce453e13a4fb08.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/libunic_langid_macros_impl-579a691294151f92.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/libyoke_derive-aa7f63b40febff86.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/libzerofrom_derive-00be0dc3f2cf0c7c.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/libzerovec_derive-88e102c86ec6d6a1.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/lib/libstd-3aad0d3d401daf04.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/bin/gcc-ld/ld.lld",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/bin/gcc-ld/ld64.lld",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/bin/gcc-ld/lld-link",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/bin/gcc-ld/wasm-ld",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/bin/rust-lld",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/bin/rust-objcopy",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/bin/wasm-component-ld",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/lib/self-contained/Scrt1.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/lib/self-contained/crt1.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/lib/self-contained/crtbegin.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/lib/self-contained/crtbeginS.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/lib/self-contained/crtend.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/lib/self-contained/crtendS.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/lib/self-contained/crti.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/lib/self-contained/crtn.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/aarch64-unknown-linux-musl/lib/self-contained/rcrt1.o",
      kind: "binary",
    },
  ],
)

## Exported declaration `filetree_x86_64`.
export let filetree_x86_64 = filetree_common.extend(
  [
    {
      path: p"usr/lib/librustc_driver-0b76769c20b60354.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/lib/libstd-286e4795762d614b.so",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/bin/gcc-ld/ld.lld",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/bin/gcc-ld/ld64.lld",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/bin/gcc-ld/lld-link",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/bin/gcc-ld/wasm-ld",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/bin/rust-lld",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/bin/rust-objcopy",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/bin/wasm-component-ld",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/lib/self-contained/Scrt1.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/lib/self-contained/crt1.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/lib/self-contained/crtbegin.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/lib/self-contained/crtbeginS.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/lib/self-contained/crtend.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/lib/self-contained/crtendS.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/lib/self-contained/crti.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/lib/self-contained/crtn.o",
      kind: "binary",
    },
    {
      path: p"usr/lib/rustlib/x86_64-unknown-linux-musl/lib/self-contained/rcrt1.o",
      kind: "binary",
    },
  ],
)

## Exported declaration `filetree`.
export let filetree = filetree_aarch64

pure rust_dist_arch(arch: Str) -> Str {
  if arch == "arm64" {
    return "aarch64"
  }

  if arch == "amd64" {
    return "x86_64"
  }

  arch
}

## Exported declaration `build`.
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
