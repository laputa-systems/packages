# LLVM Prebuilt Consumption Status

This document tracks the replacement of `repo/llvm-toolchain`'s historical
Alpine APK-sourced package with purpose-built musl LLVM prebuilt artifacts.
The producer-side plan is expected to live in:

```text
~/d/laputa-systems/llvm-prebuilt/MUSL-PREBUILT.md
```

That path was not present during the local aarch64 validation pass. This file
covers the Laputa package-manager side of the switch and records the remaining
work needed before publishing it as the durable package source.

## Current State

`repo/llvm-toolchain` has been converted locally to consume a prebuilt LLVM
tree instead of flattening Alpine APKs. The tested artifact came from:

```text
~/Downloads/clang+llvm-22.1.8-aarch64-linux-musl.zip
```

The zip contained:

```text
clang+llvm-22.1.8-aarch64-linux-musl.tar.xz
```

with SHA-256:

```text
7081172dfd956de163365e58cded731e4352d67d350c464527630c635a7d9607
```

The aarch64 package replacement has been proved through targeted local rebuilds
against a file-backed package repo:

- `llvm-toolchain-22.1.8-6`: built and `llvm-toolchain proof ok`.
- `musl-1.2.6-10`: rebuilt against the replacement toolchain and passed.
- `cmake-4.3.1-12`: rebuilt against the replacement toolchain and passed.
- `zlib-1.3.2-6`: rebuilt using the rebuilt CMake and passed.

The rebuilt `cmake`, `ctest`, and `cpack` binaries were checked with `readelf
-d`; they had no dynamic `libgcc`, `libstdc++`, or `libunwind` dependency.

The upstream release now provides both supported Laputa architectures:

```text
https://github.com/laputa-systems/llvm-prebuilt-musl/releases/tag/llvm-musl-22.1.8
```

Release artifacts:

```text
clang+llvm-22.1.8-aarch64-linux-musl.tar.xz
  SHA-256: 675f9cf871313a5672a63882d4d30dd6dd55df0aa9caee70970542eb03a23da3
clang+llvm-22.1.8-x86_64-linux-musl.tar.xz
  SHA-256: ac0bd443a1933bbd2c0efbedf6ebc97ff8ca2469e5ba65eadb966fb75f65dd1c
```

Checksums also published at:
`https://github.com/laputa-systems/llvm-prebuilt-musl/releases/download/llvm-musl-22.1.8/checksums`

PKGBUILD.xsh now consumes the upstream release artifacts instead of local files.

## Goal

Once the upstream musl prebuilt artifacts exist for both architectures,
`repo/llvm-toolchain/PKGBUILD.xsh` should consume those release archives instead
of local files:

```text
clang+llvm-<version>-aarch64-linux-musl.tar.xz
clang+llvm-<version>-x86_64-linux-musl.tar.xz
```

The package must continue to provide the same public Laputa toolchain surface:

```text
/usr/bin/cc
/usr/bin/clang
/usr/bin/c++
/usr/bin/clang++
/usr/bin/ld
/usr/bin/ld.lld
/usr/bin/ar
/usr/bin/ranlib
/usr/bin/nm
/usr/bin/objcopy
/usr/bin/objdump
/usr/bin/readelf
/usr/bin/strip
/usr/bin/llvm-ar
/usr/bin/llvm-ranlib
/usr/bin/llvm-nm
/usr/bin/llvm-objcopy
/usr/bin/llvm-objdump
/usr/bin/llvm-readelf
/usr/bin/llvm-strip
```

The XSH wrappers remain the single source of truth for Laputa compiler defaults.
Do not move those defaults back into individual packages.

## Artifact Contract

The prebuilt archive should extract to a single directory named like:

```text
clang+llvm-22.1.4-aarch64-linux-musl
```

It must contain:

- `bin/clang` or `bin/clang-22`.
- `bin/clang++` or `bin/clang++-22`.
- `bin/ld.lld` or `bin/lld`.
- LLVM binutils: `llvm-ar`, `llvm-ranlib`, `llvm-nm`, `llvm-objcopy`,
  `llvm-objdump`, `llvm-readelf` or `llvm-readobj`, and `llvm-strip`.
- Clang resource headers under `lib/clang/22/include`.
- Compiler-rt builtins for the artifact target under the Clang resource tree,
  preferably:

```text
lib/clang/22/lib/linux/libclang_rt.builtins-aarch64.a
lib/clang/22/lib/linux/libclang_rt.builtins-x86_64.a
```

The artifact must not require glibc. Tool executables must be either fully
static or musl-linked. Reject artifacts with a `/lib/ld-linux-*.so.*`
interpreter or `NEEDED libunwind.so`.

The first supported LLVM line should stay aligned with the package wrapper
paths:

```text
/usr/lib/llvm22
/usr/lib/llvm22/lib/clang/22
```

The validated local artifact is LLVM 22.1.8. Keep the package version aligned
with the producer release version, and make any downgrade or line change
explicit in the package release and proof output.

## PKGBUILD Shape

Most of this shape has already landed locally. For the publishable upstream
release, finish the source/checksum side:

1. Replace local artifact paths with upstream release URLs.
2. Fill in real SHA-256 checksums for both aarch64 and x86_64.
3. Remove any `SKIP` checksum placeholders.
4. Keep archive installation to `dest/usr/lib/llvm22`.
5. Keep tool alias normalization for versioned or alternate spellings.
6. Keep the XSH wrapper generator and wrapper installation.

The resulting build should be closer to:

```text
extract archive
install extracted tree to /usr/lib/llvm22
normalize required tool aliases inside /usr/lib/llvm22/bin
install /usr/bin wrappers
```

Avoid adding shell helper scripts unless XSH cannot express the operation. This
package should stay inspectable and deterministic.

## Wrapper Requirements

Keep the current wrapper behavior unless a proof demonstrates it is wrong:

- Always pass `--no-default-config`.
- Default to `--target=<arch>-linux-musl`.
- Default to `--sysroot=/`.
- Set `-resource-dir /usr/lib/llvm22/lib/clang/22`.
- For frontend invocations, provide Clang resource headers and `/usr/include`
  unless the caller already controls standard include handling.
- Pass `-fno-stack-protector`.
- Default to `-march=x86-64-v3` on x86_64 and `-march=armv8-a` on aarch64
  unless the caller supplied `-march=` or `-mcpu=`.
- Use `-fuse-ld=lld` for links.
- Own the musl default link line with `-nostdlib`, musl crt objects, `-lc`, and
  compiler-rt builtins so Clang cannot inject GCC runtime defaults.
- Never add `--unwindlib=libunwind`, `-lunwind`, or `--rtlib=compiler-rt`.
- C++ links may use the prebuilt tree's static
  `/usr/lib/llvm22/lib/libunwind.a` by absolute path when libc++abi needs
  unwind symbols. This must not become a dynamic `NEEDED libunwind.so`
  dependency and must not add a separate `libunwind` package dependency.

The wrapper should find compiler-rt builtins in the installed prebuilt tree. If
the current wrapper expects `/usr/lib/libclang_rt.builtins-<arch>.a`, either:

- update the wrapper to point directly at
  `/usr/lib/llvm22/lib/clang/22/lib/linux/libclang_rt.builtins-<arch>.a`, or
- install stable symlinks at `/usr/lib/libclang_rt.builtins-<arch>.a`.

Prefer direct resource-tree paths if the prebuilt artifact consistently uses the
standard Clang layout.

## Proof Updates

Strengthen `repo/llvm-toolchain/proof.xsh` when switching sources. It should
verify both the tool executable linkage and wrapper behavior.

Required checks:

- `/usr/bin/cc` is an XSH wrapper.
- The real Clang binary exists under `/usr/lib/llvm22/bin`.
- `clang`, `clang++`, `ld.lld`, and core LLVM binutils are executable.
- `readelf -l` for real tool binaries does not contain `ld-linux`.
- `readelf -d` for real tool binaries does not contain `libunwind.so`.
- Static tools with no dynamic section are accepted.
- Dynamic tools are accepted only if their interpreter is musl and their
  non-musl dependencies are included in the package.
- Clang resource headers exist.
- Compiler-rt builtins exist for the target arch.
- `cc -c` produces an object for the default target arch.
- An explicit `-target aarch64-linux-musl` compile produces an AArch64 object.
- A native proof links and runs a trivial `hello.c` without dynamic `libgcc`,
  `libgcc_s`, `libstdc++`, or `libunwind`.
- A native proof links and runs a trivial C++ program through `c++` without
  dynamic `libgcc`, `libgcc_s`, `libstdc++`, or `libunwind`.

Keep the proof temp files under stable proof-root paths such as
`/var/tmp/proof-llvm-toolchain-*`. Do not use `fs.tempdir()` in chroot package
proofs until the `/dev/fd` behavior is fixed globally.

## Dependency Cleanup

The prebuilt package should not depend on Alpine runtime libraries unless the
artifact actually needs them and ships dynamic musl-linked tools that require
packaged `.so` files.

Expected removals from `repo/llvm-toolchain`:

- `libgcc` APK source.
- `libstdc++` and `libstdc++-dev` APK sources, unless dynamic `clang++`
  genuinely needs packaged `libstdc++`.
- `libffi`, `libxml2`, `zstd-libs`, and `xz-libs` APK sources.
- Generated `files/generated/libgcc_s-*.so.1`.
- `files/generated/README.md`.
- APK symlink workaround code.
- Alpine metadata cleanup code.

Keep `deps = ["musl"]` unless the artifact is fully static and proofs show that
no installed tool requires musl at runtime. Even for static tools, `musl` may
remain useful as the target libc provider for package builds.

Do not add a dependency on `libunwind`. Static use of the LLVM prebuilt tree's
own `libunwind.a` is acceptable for C++ exception support when proofs show no
dynamic `libunwind` dependency.

## Migration Steps

- [x] **1. Upstream release published.**
      `https://github.com/laputa-systems/llvm-prebuilt-musl/releases/tag/llvm-musl-22.1.8`
      provides both `aarch64-linux-musl` and `x86_64-linux-musl` archives.

- [x] **2. Checksums recorded.**

  ```text
  clang+llvm-22.1.8-aarch64-linux-musl.tar.xz
    675f9cf871313a5672a63882d4d30dd6dd55df0aa9caee70970542eb03a23da3
  clang+llvm-22.1.8-x86_64-linux-musl.tar.xz
    ac0bd443a1933bbd2c0efbedf6ebc97ff8ca2469e5ba65eadb966fb75f65dd1c
  ```

- [x] **3. PKGBUILD sources updated** to upstream release URLs.

- [x] **4. x86_64 checksum filled in.** `checksums_x86_64` no longer `SKIP`.

- [x] **5. aarch64 checksum aligned** with the published artifact (differs from
      the local zip-sourced artifact used during initial validation).

- [x] **6a. aarch64 `llvm-toolchain` rebuilt.** `make package-test
      PKGNAME=llvm-toolchain` passed — proof ok, published.

- [ ] **6b. x86_64 `llvm-toolchain` rebuilt.** Pending — Docker image needs
      building first.

- [ ] **7. Rebuild `musl`** against the new toolchain.

- [ ] **8. Rebuild `cmake`** against the new toolchain.

- [ ] **9. Rebuild `zlib`** (or another small C/CMake package) against the new
      toolchain.

- [x] **10. Scan for stale GNU/unwind runtime defaults.** Clean — only negative
      assertions in `proof.xsh`, no stale positive references anywhere.

- [ ] **11. Publish `llvm-toolchain`** after both architecture artifacts and the
      consumer checks pass.

- [ ] **12. Rebuild and publish** any package whose release was bumped only to
      adapt to the old Alpine-sourced wrapper behavior.

## Rejection Criteria

Reject the prebuilt artifact and fix the producer repo first if any of these are
true:

- Any real tool binary requires `/lib/ld-linux-*.so.*`.
- Any real tool binary has `NEEDED libunwind.so`.
- The archive omits compiler-rt builtins for the target arch.
- The archive omits Clang resource headers.
- `cc` can compile objects but cannot link a native musl hello program through
  the wrapper defaults.
- A normal C package such as `zlib` can compile but fails at shared-library
  link time because the wrapper or artifact still assumes GCC runtime defaults.

Do not paper over a bad artifact by adding glibc compatibility, GNU runtime
compatibility, a dynamic/external libunwind dependency, or Alpine APK
flattening back into `repo/llvm-toolchain`.
