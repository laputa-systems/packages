# Agent Guide

This repository owns the Laputa package manager and package repository. Keep it
focused on package definitions, PM behavior, PM tests, and documentation for the
Laputa userspace and packaging philosophy.

## Output

- Do not narrate obvious tool use or repeat command output the user can already
  see.
- Summarize findings, decisions, and verification results.
- When reporting a failure, include the command and why it matters.

## Working Areas

- `pm.xsh` and `pm/`: package manager CLI and modules.
- `repo/`: package definitions and package proofs.
- `tests/xsh/`: PM tests and package fixtures.
- `PM.md`, `LAPUTA.md`, and `M4.md`: PM, packaging, and userspace guidance.

## PM Module Ownership

- `pm.xsh`: process entrypoint only. It imports `pm/cli.xsh`, forwards argv,
  and keeps no package manager behavior.
- `pm/cli.xsh`: command usage, argument parsing, default root/work/out context,
  package-dir detection, top-level dispatch, extension fallback, and small
  command adapters that compose domain modules.
- `pm/world.xsh`: world package expansion, dependency/tranche planning, rebuild
  explanations, rel propagation, world cache naming, world state, tranche build
  execution, build log routing, staged artifact verification, and world
  upload/sync orchestration.
- `pm/repo.xsh`: repository build/upload/export flows, package staging, staged
  index mutation, repo artifact verification, source mirror export upload, and
  repo export synchronization.
- `pm/build.xsh`: local package build, chroot build, proof execution, build log
  handling, chroot runner seeding, and build cache preservation.
- `pm/install.xsh`: remote package install, local built-package install, remove
  flows, package DB inspection, manifest ownership checks used by
  install/remove, and installed-package tree/search/outdated reporting.
- `pm/local.xsh`: package definition loading, dependency ordering, local index
  writing, source checksum/update/download commands, and shared package
  metadata/manifest helpers used by build, install, and repo modules.
- `pm/buildroot.xsh`: dependency-set installation and chroot-base preparation
  helpers shared by world execution and package build flows.
- `pm/remote.xsh`: remote transport and index decoding.
- `pm/sources.xsh`: source resolution and mirroring.
- `pm/util.xsh`: small shared helpers.
- `pm/types.xsh`: stable shared types.

Preserve this ownership model when changing PM code. Small cleanups are fine
when they reduce duplication, narrow APIs, or make effectful boundaries clearer.
Avoid new abstractions that only rename existing complexity.

Keep `build-set` under review. It intentionally remains in `pm/cli.xsh` because
it combines repo staging with world-style dependency semantics; move it only if
a cleaner dependency direction appears. Keep package-facing helper modules
(`pm/make.xsh`, `pm/meson.xsh`, `pm/proof.xsh`, `pm/configure.xsh`) stable
unless a real package API issue appears.

Some packages intentionally carry generated source inputs under
`files/generated/` or package-local `files/*.c`/`files/*.h`. These are package
sources, not build leftovers, when they replace heavyweight generators that are
not yet part of the Laputa userspace. Keep the generator path documented in the
package or nearby docs, and prefer regenerating them through XSH package tools
once the native generator exists.

The integration repository lives at `~/d/laputa-systems/laputa` and owns Docker
images, QEMU harnesses, installer image tooling, Linux iteration workflows, and
hardware-specific notes.

## Rules

- Keep changes scoped to packages, PM behavior, package tests, or package docs.
- Prefer existing package and PM patterns over new abstractions.
- Preserve comments that explain why something exists.
- Do not add dependencies unless there is a clear need and no local equivalent.
- Do not run pre-commit hooks. Do not push.
- Do not build release XSH binaries in this repository. Consume published XSH
  release artifacts instead.

## Verification

Choose the narrowest useful proof first. For package changes, prefer PM
load/type checks, then integration checks from `~/d/laputa-systems/laputa` with
`LAPUTA_PACKAGES_ROOT=$HOME/d/laputa-systems/packages`, for example:

```sh
make package-test PKGNAME=<name> LAPUTA_PACKAGES_ROOT=$HOME/d/laputa-systems/packages
```

Most PM tests need Linux filesystem/process behavior. From this repo, run:

```sh
make test
```

`make test` builds a scratch-runtime test image, preferring the local sibling
XSH Linux build under `../xsh/target/<arch>-unknown-linux-musl/debug` and
falling back to the published XSH release when no local build exists. It runs
`xsht test --cov --cov-json target/coverage/pm.json tests/xsh/pm.xsh` against
the checkout mounted at `/src/packages`. Inspect the coverage JSON after the run
for PM source line/proc coverage by file.

Current PM coverage baseline from `make test`: `tests/xsh/pm.xsh` covers
1600/6914 PM source lines (23.1%) and 223/401 procs (55.6%). Treat coverage as
a refactor aid, not a metric target. Do not add trivial tests just to raise the
percentage.

The PM suite is expected to protect broad behavior, including package loading
and dependency ordering, local build/proof execution, remote install from
tarballs and metadata sidecars, source checksum/update/mirror flows, world-plan
rel propagation and rebuild explanations, resumable world-build state, dirty
filesystem detection, and upload/index mutation paths.

Keep PM tests behavior-oriented. Do not add trivial tests only to raise the
percentage. Add tests when behavior changes, when a module boundary exposes an
unprotected contract, or when a bug fix needs regression coverage.

For world changes, use:

```sh
xsh pm.xsh -- world-plan repo --arch <aarch64|x86_64>
```

For routine PM refactor checks, use:

```sh
../xsh/target/debug/xsht check pm.xsh pm/*.xsh
make test
```

For integration smoke testing from the sibling Laputa repo, use:

```sh
make world-build WORLD_TO_TRANCHE=0 WORLD_JOBS=1 LAPUTA_PACKAGES_ROOT=$HOME/d/laputa-systems/packages
```

## CI Workflows

- `.github/workflows/laputa-package-publish.yml`: builds, proves, and publishes
  one package to the mirror for `arm64` or `amd64`, using the integration repo's
  reusable build base.
