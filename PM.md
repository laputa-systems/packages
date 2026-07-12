# Package Manager

`pm.xsh` is the Laputa package manager CLI. `pm/` contains the
ordinary XSH modules for package loading, source staging, local installs,
remote indexes, uploads, hooks, and helpers. PM policy lives here rather than
in the XSH standard library.

## Package Contract

Package definitions are XSH modules under `repo/<pkg>/PKGBUILD.xsh`.
Required exports:

- `name: Str`
- `ver: Str`
- `rel: Str`
- `deps: List[Str]`
- `mkdeps_host: List[Str]`
- `upstream_sources: List[UpstreamSource]`
- `filetree: List[{path: Path, kind: Str}]`
- `build(dest: Path) -> Result[Unit]`

Optional exports:

- `nostrip: Bool`
- `mkdeps_target: List[Str]`
- `source_mirror: Bool`
- `prepare(src: Path) -> Result[Unit]`
- `prepare_sources(src: Path) -> Result[Unit]`
- `pre_install(root: Path) -> Result[Unit]`
- `post_install(root: Path) -> Result[Unit]`
- `pre_remove(root: Path) -> Result[Unit]`
- `post_remove(root: Path) -> Result[Unit]`

`deps` are runtime dependencies. `mkdeps_host` are executable build-time tools.
`mkdeps_target` are target-side build metadata packages such as headers,
pkg-config files, protocol XML, and other files needed while compiling but not
needed by installed runtime files. The PM base runtime includes `laputa-pm`, so
package definitions should not list it just to get `/usr/bin/pm`,
`/bin/xsh`, or XSH core command links.

`filetree` declares the completed payload tree. Each `file` and `symlink` entry
must be produced by `build()`, and every produced file must be declared either
explicitly or beneath a `tree` directory entry. An ELF executable or library
must be declared explicitly as `binary`; PM validates that classification and
automatically runs `llvm-strip --strip-unneeded` on those entries before the
package archive and proof are created. Packages that declare binaries must list
`llvm-toolchain` in `mkdeps_host` so the stripping tool is available in the build
root. `tree` entries are useful for large
header or documentation trees, but ELF files and symlinks inside them still
need explicit entries. `nostrip: true` remains an escape hatch for packages
that intentionally preserve binary symbols.

`upstream_sources` is an ordered list of records containing a source path or
URL, a materialization kind, and target-architecture checksum records. Source
URLs may use `VERSION`, `RELEASE`, `MAJOR`, `MINOR`, `PATCH`, `IDENT`,
`PACKAGE`, `ARCH`, `GOARCH`, `TARGET_ARCH`, `TARGET_GOARCH`, and
`TARGET_TRIPLE`. `ARCH` is the target architecture, not the build host.

`kind` is `auto`, `archive`, `zip`, `cpio`, `file`, `directory`, or `git`.
`file` is used for direct binary inputs even when the upstream filename ends in
an archive-looking suffix. Each checksum record names either a target arch or
`all`. A regular file without a selected checksum is invalid. `source_mirror:
false` keeps the input in the private build cache without publishing a public
source mirror.

PM materializes the selected inputs, runs the optional `prepare_sources(src)`
hook, removes VCS administrative directories, and packs the prepared tree as a
deterministic bzip2 tar archive. A valid source mirror is tried before upstream
acquisition; PM verifies its `source_sha256`, extracts it, and runs
`prepare_sources` again. A missing, corrupt, or unusable mirror falls back to
the declared upstream inputs.

Local mirrors are stored as
`.out/source-mirrors/<name>-<ver>-<rel>-<arch>.tar.bz2` with a
`.manifest.json` sidecar. Published mirrors use the derived path
`sources/<name>/<name>-<ver>-<rel>-<arch>-src.tar.bz2`; the index stores the
archive hash in `source_sha256` and does not store a source filename.
`pm source-audit` checks local mirror and manifest presence and hashes.

Source preparation and normalization are part of the package input contract.
When either changes, bump `rel` and rebuild/prove the package before reusing or
publishing a mirror. A mirror is staged during a build but is published only
after the package tarball and proof succeed. Packages with `source_mirror:
false` remain buildable but publish no source artifact.

## Service Definitions

A package that provides an `xinit` service must define it in a `service.xsh`
file next to its `PKGBUILD.xsh`, mirroring the required `proof.xsh`. The file
exports one `service` record using the `xinit` service contract (see the xinit
`docs/INIT.md`); `build()` installs it under
`/usr/lib/xinit/services/<name>.xsh`. List `p"service.xsh"` in
`upstream_sources` (with a
`SKIP` checksum, like other repo-local files) so it is staged for `build()`.

The contract is enforced during the package proof and is bidirectional:

- A package whose manifest installs any `/usr/lib/xinit/services/*.xsh` file
  must ship a `service.xsh`, otherwise the proof fails.
- A package that ships `service.xsh` must install it under
  `/usr/lib/xinit/services/`, otherwise the proof fails.

When `service.xsh` is present the proof runs `xinit check` on it, so a malformed
or undeclared service fails the build instead of the running system. The proof
locates `xinit` from `XINIT_HOST`, then `/usr/bin/xinit`, then `PATH`; a service
package proof fails with an actionable error when none is found.

## Commands

Common commands:

```text
pm build REPO_DIR PKGDIR...
pm build-set REPO_DIR PKGDIR...
pm build-upload-set REPO_DIR PKGDIR...
pm build-install ROOT BUILD_ROOT WORK OUT PKGDIR...
pm world-plan PKGDIR... [--arch ARCH] [--build] [--upload] [--to-tranche N] [-j N|--jobs N]
pm install ROOT WORK OUT PKG...
pm remove ROOT WORK OUT PKG...
pm tree ROOT WORK OUT [PKG...]
pm list ROOT WORK OUT
pm info ROOT WORK OUT PKG
pm search ROOT WORK OUT QUERY
pm outdated ROOT WORK OUT
pm update ROOT WORK OUT
pm upgrade ROOT WORK OUT
pm checksum ROOT WORK OUT PKGDIR...
pm update-checksums ROOT WORK OUT PKGDIR...
pm upload ROOT WORK OUT PKGDIR...
pm source-audit ROOT WORK OUT PKGDIR...
```

Use `make update-checksums` from the package repo to refresh checksums for all
`repo/*` packages in parallel. Set `PKGDIRS="repo/bison repo/flex"` for a
targeted run, or `UPDATE_CHECKSUM_JOBS=4` to adjust parallelism.

`pm.xsh` is normally invoked through XSH's script separator:

```sh
xsh pm.xsh -- world-plan repo --arch x86_64
```

To run the PM suite directly on a Linux host with the checked-out debug XSH:

```sh
make test-native XSH_ROOT=$HOME/d/laputa-systems/xsh
```

This disables the package build and proof chroots. The Docker-backed `make
test` remains the runtime-isolated suite.

## World Rebuilds

`world-plan` expands package roots such as `repo`, computes dependency
tranches using runtime deps, `mkdeps_host`, and `mkdeps_target`, and prints a
human-readable plan. The default arch is the host arch; `--arch aarch64` and
`--arch x86_64` are supported.

The staging repo is `~/.cache/laputa/world-<hash>`. The hash covers `pm.xsh`,
PM modules, target arch, and selected package-local files, so package metadata
edits invalidate an incompatible world while preserving resumability for the
same plan.

`--build` builds tranche by tranche. Packages within a tranche build in
parallel; `-j`/`--jobs` controls package concurrency and defaults to
`XSH_PM_WORLD_JOBS` or the host CPU count. `--to-tranche N` limits the build so
a world can be resumed incrementally.

`world-plan` compares local package versions and metadata against the remote
repo for the selected arch. Package versions and rels declared in local
`PKGBUILD.xsh` files are authoritative; a build fails if a declared release is
behind the selected architecture's remote release. Bump the declaration
explicitly before rebuilding.

`--upload` refuses to publish until the staged world is complete and every
package proof has passed. It uploads the complete staged package set and then
switches the remote index.

## Builds And Proofs

`build-set` and `build-install` are the normal package proof paths. They build
inside PM-managed Laputa roots instead of relying on ambient host tools.

`build-install` uses two roots:

- `ROOT`: runtime deps and built packages.
- `BUILD_ROOT`: runtime deps, `mkdeps_host`, `mkdeps_target`, tool runtime, and
  built packages.

For native cross world builds, PM keeps the target package root and native build
tool root separate. `mkdeps_target` are staged for the target arch alongside
runtime deps. `mkdeps_host` are staged for the build arch so executable tools run on
the host.

Each package source tree is copied into `/var/tmp/pm-build/<pkg-id>` inside the
build root. PM runs `prepare` and `build` after entering the chroot. The package
tarball is installed into both roots before later local packages build.

Every package proof runs after its tarball is created. Proof roots contain the
candidate package plus its dependencies and seeded XSH/PM runtime.

Successful builds report the final compressed tarball size in KiB after
stripping and proof completion. World builds include the same size on their
completion line.

## Remote Repos

Remote install/update operations use `XSH_PM_REPO`, then `LAPUTA_REPO`, then
the default mirror `https://laputa.17166969.xyz`. Public package URLs use
`XSH_PM_PUBLIC_REPO` when set.

Authenticated uploads use `LAPUTA_TOKEN`. A repo-local `.env` is loaded by the
Makefile publish path when the variable is not already present.

The remote index records package metadata and a sidecar metadata hash. PM uses
that hash to detect local package metadata changes even when `ver-rel` has not
changed.

## Installed State

The installed package database records version, deps, mkdeps_host,
mkdeps_target, manifest entries, and `/etc` checksums. Installs use
manifest ownership checks to avoid dirty overwrites. Removes refuse to break
dependent packages.

`pm tree` renders dependency trees from the installed database. Repeated shared
packages are marked with `(*)` and expanded only at their first appearance.

## Extensions And Hooks

Executable `pm-*` files in `PATH` become extension actions. `pm ACTION ROOT
WORK OUT [ARGS...]` runs `pm-ACTION` with:

- `XSH_PM_ROOT`
- `XSH_PM_WORK`
- `XSH_PM_OUT`
- `XSH_PM_ACTION`
- `XSH_PM_ARGS`

`XSH_PM_HOOKS` is a colon-separated list of executable lifecycle hooks.
`LAPUTA_HOOK` remains a compatibility alias when `XSH_PM_HOOKS` is unset.
Hooks run for build, install, remove, update, and upload phases with
`XSH_PM_HOOK`, `XSH_PM_PACKAGE`, and `XSH_PM_EXTRA` set.

## Design Notes

- Source verification uses hash APIs and traversal-safe archive extraction.
- Process execution uses structured argv, not shell strings.
- Package builds must not depend on an ambient POSIX `/bin/sh`; recipes should
  call tools directly through structured argv, including install phases that
  build systems may otherwise route through shell commands.
- Network transfers use `net.download` and `net.request`.
- Tokens are never logged or serialized into traces.
- Mutating sibling Laputa repositories is out of scope.
