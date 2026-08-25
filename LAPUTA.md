# Laputa Userspace

Laputa is a small Linux userspace built around XSH, musl, native package
proofs, and explicit service/runtime contracts. It is not a POSIX shell
compatibility project and not a systemd-shaped replacement with different
names. Compatibility is useful only when the boundary remains narrow and
provable.

## Intent

Laputa exists to make systems glue inspectable. Package recipes, proofs, boot
hooks, service definitions, generated headers, and source processing should be
ordinary typed XSH programs using structured argv, explicit errors, typed
paths, checked archives, hashes, scoped environment changes, and runtime
traces.

When upstream uses shell, Python, awk, sed, autoconf, or Makefile fragments for
small generation or install glue, Laputa first asks whether that logic belongs
in XSH or a small native tool. New runtimes are accepted only when the package
needs them for real capability, not incidental build glue.

## Principles

- One capability, one owner.
- Runtime dependencies are installed files needed by installed files.
- Build dependencies are tools needed to produce those files.
- Generated data is source-adjacent and reproducible or intentionally pinned.
- No ambient `/bin/sh` execution substrate for package policy.
- Build recipes must not assume a POSIX shell exists at `/bin/sh`,
  `/usr/bin/sh`, or through `SHELL`.
- Proofs exercise behavior rather than inheriting distro convention.

## Packages

Laputa packages are XSH modules under `repo/<pkg>`. PM owns dependency
ordering, source verification, archive extraction, manifests, install/remove
lifecycle, package database state, remote indexes, world rebuilds, and uploads.

Package recipes should prefer:

- XSH filesystem APIs instead of install shell fragments;
- structured process arguments instead of shell strings;
- `pm.make`, `pm.configure`, or direct compiler invocations where that is the
  smallest correct build;
- explicit runtime deps and `mkdeps_host`;
- package-local proofs that validate the installed artifact.

See `PM.md` for the current PM contract.

Package recipes must avoid hidden shell handoffs as well as obvious shell
scripts. Build tools often encode install or generator commands as `cd ... &&
...` and run them through `/bin/sh -c`; those paths are not acceptable package
interfaces. Prefer direct structured entrypoints such as `cmake -P
cmake_install.cmake` inside an XSH `cd` block, direct compiler/tool invocations,
or small `#!/bin/xsh` wrapper scripts. A package may install an actual shell
when the shell is the package capability being proved, but other packages must
not depend on an ambient POSIX shell as build glue.

### Packaging Guidelines

Keep package builds narrow. Laputa packages should install the capability the
package is meant to provide, plus the runtime files that capability needs. They
should not inherit a distro's default test, documentation, locale, completion,
or optional feature surface unless that surface is part of the package contract
or needed by another proved package.

Disabling docs, tests, example programs, benchmarks, optional protocol stacks,
large locale sets, or desktop integration extras is desirable when those files
do not affect the installed capability being proved. Prefer explicit configure
or build-system options for those exclusions, and record the reason when the
choice is not obvious from the package name.

Generated files are acceptable package inputs when they are source-adjacent,
pinned, and covered by the package proof or by a follow-up regeneration plan.
For small generators, prefer XSH-native generation over adding Python, shell,
awk, sed, or a new runtime to the bootstrap surface. For large upstream
generators, make the tradeoff explicit in the package notes.

Small generated headers should be produced by the package recipe. For example,
`foot-minimal` and `fcft-minimal` generate their version headers in XSH instead
of vendoring them. Larger generated artifacts such as Unicode tables,
fontconfig language tables, parser outputs, and Linux arch/generated headers
may remain pinned package inputs until the generator itself is part of the
proved bootstrap surface.

Native cross builds may use native build-root tools such as muon, CMake,
pkgconf, samurai, flex, bison, m4, wayland-scanner, or compiler tools, but those
tools must come from the staged Laputa build root rather than from the ambient
host. Target libraries, headers, pkg-config files, and protocol data must come
from the target root.

Prebuilt package payloads are acceptable only when the package is unusually
hard to bootstrap without already having a large toolchain.
`cargo` and `llvm` are the current strategic exceptions. Treat
them as explicit bootstrap anchors, keep their source URLs and hashes pinned,
and prefer source-built packages for ordinary libraries and tools.

**Do not use pre-built packages from other distributions** (Alpine, Debian,
Arch, etc.) as Laputa package payloads.  Every package that is not a named
bootstrap anchor must build from its upstream source tree inside the Laputa
chroot, using `pm.make`, `pm.configure`, cmake+ninja, or muon.  This keeps the
package graph provable, reproducible, and owned by the Laputa toolchain rather
than by a foreign distribution's build decisions.

The durable C/C++ toolchain contract is LLVM plus musl, not GNU runtime
compatibility. Packages must not depend on `libgcc`, `libgcc_s`, or
`libstdc++` as runtime dependencies, and the package manager must not add those
libraries as implicit compiler defaults. When an upstream build assumes GNU
runtime pieces, patch the package or wrapper invocation to use the Laputa
LLVM/musl surface instead of reintroducing GNU compatibility libraries.

The `llvm-toolchain` package itself may provide narrow GNU-compatibility stubs
(`crtbeginS.o`, `crtendS.o`, `libgcc_s.so`) built from the prebuilt LLVM
tree's own `libunwind.a`. These stubs exist for packages (e.g. `sudo-rs`) that
hard-code GNU runtime object or library names and cannot be patched around
practically. They are toolchain-owned implementation details, not a separate
compatibility layer, and must not grow into a general `libgcc` replacement.
Packages that can build without them should do so.

Runtime `deps` should mean installed files needed by installed files. `mkdeps_host`
should mean executable build tools. `mkdeps_target` should mean target-side
headers, pkg-config files, protocol XML, or other target metadata needed to
build the package but not needed by its installed runtime files.

Hardcoded configure and target-probe answers should be isolated behind PM
helpers when they are shared across packages. `pm.target` owns common musl ABI
facts such as LP64 type sizes and suffixes. Package-local probe maps are
acceptable only when they are narrow, documented, and tied to the target tuple
being built.

## Native Build Base

The reusable native base is the `build-essential-native` package and the
`laputa-bootstrapped-build-essential-native` image. It starts from `scratch`
plus a pinned XSH release artifact, then installs package-built tools from the
Laputa mirror. It does not copy Alpine tools or host runtime libraries into the
durable package-build base.

The base contains the common C/C++ and package tooling surface: musl, LLVM,
pkgconf, samurai, CMake, m4, flex, bison, Linux, muon, CA certificates, and the
package-owned runtime closure required by those tools.

Normal package proofs use PM-managed chroots. `pm build-set`, `pm
build-install`, and `pm world-plan --build` install declared deps and `mkdeps_host`
into a build root, copy the prepared source tree into `/var/tmp/pm-build`, and
run package hooks after entering the chroot.

## World Rebuilds

`pm world-plan repo --arch <aarch64|x86_64>` computes the rebuild order
for the package world. A staging repo lives under `~/.cache/laputa/world-<hash>`
and can be resumed while the plan hash is stable. Packages in the same tranche
build in parallel. `--to-tranche N` supports incremental catch-up.

`world-plan` compares local metadata with the remote mirror and treats package
versions and rels declared in `PKGBUILD.xsh` as authoritative. A build fails if
a declaration is behind the selected architecture's published release, so rel
bump edits must be explicit. `--upload` refuses to publish until the staged
world is fully built and proved.

## Linux

The `linux` package owns both the boot kernel at `/boot/vmlinuz` and kernel
UAPI headers under `/usr/include`. There is no separate kernel-header package.

Linux package inputs are arch-specific:

- `repo/linux/files/config/aarch64/base-aarch64.fragment`
- `repo/linux/files/config/x86_64/base-x86_64.fragment`

The current native Kbuild implementation is arm64-focused. The x86_64 config
and package selection boundary exist so amd64 builds cannot accidentally
publish an arm64 kernel as an x86_64 package while x86_64 Kbuild/link support
is still being implemented.

## Device And Session Shape

Laputa prefers separable device and session components:

- a small device manager owns `/dev` population and coldplug/hotplug policy;
- a separate `libudev.so.1` compatibility provider satisfies legacy consumers;
- seat access is mediated without logind or DBus;
- service definitions and lifecycle hooks are XSH programs.

The current desktop path uses `mdevd`, `libudev-zero`, `seatd`, wlroots, dwl,
and foot to prove DRM/input/seat/Wayland behavior without systemd, elogind,
DBus, portals, X11, PulseAudio, or PipeWire.

## Proofs

Durable proof targets:

- `make build-essential-native`: reusable package-build base.
- `make package-test PKGNAME=<name>`: one package and its package proof.
- `make proof-rootfs`: core rootfs proof.
- `make dwl-foot-minimal-test`: compositor/terminal image proof.
- `make installer-qemu-test`: arm64 installer/installed-target proof.

Proofs should show the package graph, dynamic library closure, generated files,
service startup, device/filesystem state, permissions, and user-visible
behavior relevant to the capability under test.

## Rewrite Pressure

Good candidates for future Rust, Seed, or XSH ownership are narrow privileged
or parser-heavy components: device event handling, libudev-compatible
introspection, seat mediation, EDID/display metadata parsing, Wayland protocol
generation, and small input/font/keyboard support helpers.

The goal is not to rewrite large domains for its own sake. The goal is to own
foundational policy and unsafe boundaries when the proof path is ready.

## Simplification Todo

The current world rebuild is intentionally lean. The remaining large
simplification item is intentionally deferred:

- Replace placeholder packages such as `mesa-minimal` with real minimal source
  builds once the graphics stack proof needs that capability.
