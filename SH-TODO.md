# Shell Surface Todo

Laputa package builds must not depend on an ambient POSIX `/bin/sh`. The
current package-build glue has been converted away from generated shell
wrappers and hidden `samu install` shell handoffs, but a few shell surfaces
remain intentionally or historically. Track them here until each is removed,
made XSH-native, or explicitly accepted as a package capability.

## Done

- CMake package installs no longer use generated Ninja `cd ... && cmake -P ...`
  shell commands; recipes call `cmake -P cmake_install.cmake` from XSH `cd`
  blocks.
- Wayland scanner native-cross recipes no longer generate `#!/bin/sh` wrapper
  scripts; generated Ninja files point directly at `wayland-scanner`.
- Installed compatibility wrappers for `yacc` and `ldd` are generated as
  `#!/bin/xsh` scripts.
- PM native-cross compiler shims are generated as `#!/bin/xsh` scripts.

## Open

### PM seeded `/bin/sh` compatibility shim

Files:

- `pm/build.xsh`
- `pm/chroot-run.xsh`

PM currently seeds `/usr/bin/sh` and `/bin/sh` in build/proof roots with an
XSH-backed compatibility script, and sets `SHELL=/bin/xshi` for package
execution. This avoids a real POSIX shell dependency but still preserves an
ambient `/bin/sh` path for tools that assume one.

Decide whether this should remain as a deliberately narrow compatibility
escape hatch, become opt-in per package, or be removed once remaining callers
are gone. If it remains, document exactly which syntax it supports and make
failures point at the package that invoked it.

### wlroots generated helper references

File: `repo/wlroots0.19-mesa/PKGBUILD.xsh`

The patched Meson snippets still mention upstream helper names:

- `gen_pnpids.sh`
- `embed.sh`

The current recipe patches those generation paths away enough to avoid running
the shell helpers. Verify with a clean package build, then either remove the
dead references from the patched Meson text or replace the helper flow with
direct XSH/native generation.

### Runtime packages that intentionally expose shell semantics

Files:

- `repo/dwl-minimal/PKGBUILD.xsh`
- `repo/tmux/proof.xsh`
- `repo/m4/files/m4.xsh`

These are not hidden package-build glue:

- `dwl-minimal` carries upstream `SHCMD`/`execl("/bin/sh", "-c", ...)`
  runtime behavior.
- `tmux` proof starts a shell inside a tmux session.
- `m4` implements shell-facing builtins such as `esyscmd` and `syscmd`.

For each package, decide whether shell semantics are part of the capability
being proved. If not, patch to XSH/direct process execution. If yes, ensure the
runtime dependency and proof say that explicitly.

### Installed `.sh` payloads

Files:

- `repo/less/PKGBUILD.xsh`

`less` installs `less-osc8-open.sh` as `/usr/libexec/less-osc8-open`. Inspect
whether the installed helper is actually needed by the package proof. If it is,
port it to XSH or a direct native helper; if not, stop installing it.

### Linux test shell commands

File: `repo/linux/tests/main.xsh`

Two Linux package unit tests still use `/bin/sh -c` for compact file-generation
commands. Replace those with a tiny checked XSH helper or direct file writes so
tests do not normalize shell availability.

### Generated-file names ending in `.sh`

Files:

- `repo/foot-minimal/PKGBUILD.xsh`
- `repo/fcft-minimal/PKGBUILD.xsh`
- `repo/musl/PKGBUILD.xsh`

These references are currently comments or upstream file names such as
`generate-version.sh` and `tools/version.sh`. They are not executed. Leave them
unless nearby generation logic is rewritten and the names become misleading.
