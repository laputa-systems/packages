# LLVM Prebuilt Consumption Plan

This document is a handoff plan for replacing `repo/llvm-toolchain`'s current
Alpine APK-sourced package with a purpose-built musl LLVM prebuilt artifact.
The producer-side plan lives in:

```text
~/d/laputa-systems/llvm-prebuilt/MUSL-PREBUILT.md
```

Read that document first. It defines the artifact contract this package should
consume. This file only covers the Laputa package-manager side of the switch.

## Goal

Once the musl prebuilt artifacts exist, `repo/llvm-toolchain/PKGBUILD.xsh`
should stop flattening Alpine APK payloads and instead install a single
Clang/LLVM distribution archive:

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

If the producer publishes LLVM 22.1.4 first, it is acceptable for the package
version to move from Alpine's `22.1.8` back to `22.1.4`, but make that choice
explicit in the package release and proof output.

## PKGBUILD Shape

When the artifacts are ready, simplify `repo/llvm-toolchain/PKGBUILD.xsh`:

1. Replace the Alpine APK source list with the two musl archive URLs, one per
   supported arch.
2. Remove generated `libgcc_s` inputs and their documentation.
3. Remove APK extraction helpers, Alpine metadata cleanup, and generated
   `libgcc_s.so.1` installation.
4. Extract the archive into `dest`.
5. Move or copy the extracted tree to `dest/usr/lib/llvm22`.
6. Normalize tool names if the archive only provides versioned or alternate
   spellings.
7. Keep the XSH wrapper generator and wrapper installation.

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
- A native proof links and runs a trivial `hello.c` without `libgcc`,
  `libgcc_s`, or libunwind.

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

Do not add a dependency on `libunwind`.

## Migration Steps

1. Confirm the prebuilt release includes both `aarch64-linux-musl` and
   `x86_64-linux-musl` archives.
2. Download each archive and record SHA-256 checksums.
3. Update `repo/llvm-toolchain/PKGBUILD.xsh` sources and checksums.
4. Replace APK extraction with prebuilt archive installation.
5. Normalize tool aliases in `/usr/lib/llvm22/bin`.
6. Update wrappers only where the installed layout changed.
7. Strengthen `repo/llvm-toolchain/proof.xsh` with the linkage checks above.
8. Run `make package-test PKGNAME=llvm-toolchain` from the integration repo.
9. Run `make package-test PKGNAME=musl`.
10. Run `make package-test PKGNAME=zlib` or another small C/CMake package.
11. Scan for stale unwind/runtime defaults:

```sh
rg -n -- '--unwindlib|unwindlib|-lunwind|--rtlib=compiler-rt|rtlib=compiler-rt|crtbeginS|crtendS' pm.xsh pm repo
```

12. Publish `llvm-toolchain` only after the consumer checks pass.
13. Rebuild and publish any package whose release was bumped only to adapt to
    the old Alpine-sourced wrapper behavior.

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

Do not paper over a bad artifact by adding glibc compatibility, libunwind, or
Alpine APK flattening back into `repo/llvm-toolchain`.
