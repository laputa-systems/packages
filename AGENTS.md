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

For world changes, use:

```sh
xsh pm.xsh -- world-plan repo --arch <aarch64|x86_64>
```

## CI Workflows

- `.github/workflows/laputa-package-publish.yml`: builds, proves, and publishes
  one package to the mirror for `arm64` or `amd64`, using the integration repo's
  reusable build base.
