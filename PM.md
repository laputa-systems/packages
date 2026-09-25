# Package Manager

`pm.xsh` is the typed Laputa package manager. It turns package recipes into a
deterministic `BuildPlan`, executes only that plan through immutable artifacts,
publishes verified snapshots, and composes runtime-only root generations.

## Package Contract

Recipes live at `repo/<package>/PKGBUILD.xsh` and export:

- `name: Str`, `ver: Str`, and positive `rel: Str`;
- `package_kind: "payload" | "meta"`;
- `deps`, `mkdeps_host`, and optional `mkdeps_target`;
- `upstream_sources` and `filetree`;
- `build(dest: Path)` for payload packages.

Payload recipes also carry `proof.xsh`. Metapackages declare no payload
`filetree`; they may contain dependencies only. `filetree` is the exact output
contract: each file or symlink is explicit, while a `tree` declaration covers
ordinary descendants. ELF outputs must be declared as `binary`.

Recipe loading is quarantined in `pm/recipe.xsh`. The rest of PM receives only
typed `Package` values; runtime lifecycle hooks are not part of the package
contract. Immutable root preflight rejects ownership conflicts before any
generation is written.

`upstream_sources` selects `auto`, `archive`, `zip`, `cpio`, `file`,
`directory`, or `git` materialization. A `SKIP` checksum is accepted only for a
relative repository-local source. Source preparation is part of the package
build identity.

## Commands

```text
pm repo check [--repo PATH]
pm repo plan [--repo PATH] (--all | --root PACKAGE...) \
  [--target TARGET] --output PLAN
pm repo show PLAN
pm repo build PLAN --store STORE [-j N|--jobs N]
pm repo publish PLAN --store STORE
pm repo checksum [--repo PATH] PACKAGE...
pm repo update-checksums [--repo PATH] PACKAGE...
pm repo source-audit [--repo PATH] PACKAGE...

pm root compose PLAN \
  --store STORE \
  --runtime-root PACKAGE... \
  --output GENERATION
pm root inspect GENERATION
pm store verify --store STORE
pm store extract PLAN --store STORE --package PACKAGE --path PATH --output FILE
```

`repo plan` is the only resolution boundary. It records the target, typed
dependency graph, remote retrieval identity, build/proof inputs, executor
identity, action reasons, and sorted artifact keys in an atomically written
plan. `aarch64-linux-musl` remains the default build target.
`x86_64-linux-musl` can be planned and inspected with target-specific source
checksums, filetrees, remote index entries, and artifact keys. `repo build`
rejects that target before creating a store. Artifact receipts can carry either
target and reject cross-target reuse of the same key. Root preflight and
composition preserve an explicit target and reject mixed receipts. Generation
plans and receipts also preserve x86_64 when supplied with verified x86_64
artifacts. Native x86_64 package execution remains pending.

`repo build` discovers the repository only by walking to a directory containing
both `pm.xsh` and `repo/`. It executes the saved plan with `pm/execute.xsh`;
artifact-store receipts are the sole resume state. `-j` changes scheduling only,
never a plan or artifact key.

`repo publish` selects the completed plan nodes from verified receipts, uploads
immutable payload, metadata, and proof objects, then updates the index last.
For network repositories it reads `LAPUTA_TOKEN` from the process environment;
PM does not store credentials. `file://` repositories need no token.

`root compose` selects only typed runtime edges from the saved plan and writes
an immutable generation receipt. It never installs into a live root. `root
inspect` and `store verify` are read-only receipt checks.
`store extract` copies one manifest-declared file from the exact artifact named
by a saved BuildPlan. `pm/generation_adapter.xsh::generation_adapter_copy_manifest_file`
checks the Store receipt and payload digest, verifies the file against artifact
metadata, and publishes the output by atomic rename. `PATH` must be canonical
and relative. Image builders use it for kernel files that are deliberately
absent from the runtime generation.
For a profile-owned overlay, `pm/generation.xsh::plan_profile` selects the
runtime closure and binds the overlay digest into its identity.
`write_generation_plan` and `read_generation_plan` persist and validate that
typed plan before `compose` uses it; the saved plan must match the BuildPlan and
overlay used for execution.

## Source Mirrors

Packages may keep source mirrors in a repository `.out/source-mirrors` cache.
`repo source-audit` verifies that cache for its explicitly named packages.
`source_mirror: false` keeps an input private to execution.

## Catalog and graph

`pm/catalog.xsh` is the repository-wide typed catalog boundary. It rejects
duplicate package names and malformed recipes before resolution.
`pm/policy.xsh` contains the explicit aarch64 bootstrap exceptions, while
`pm/graph.xsh` resolves stable runtime, build-host, and build-target edges.
The graph never adds an implicit package-manager dependency. Its sorted
topological levels and typed edge kinds are persisted in `BuildPlan`.
The native Docker adapter passes `XSH_PM_BOOTSTRAP_LLVM_ROOT=/usr/lib/llvm23`
for `gnu-stubs`: its LLVM edge is a bootstrap seed, so the recipe must use the
preseeded compiler while the replacement LLVM package is built.

## Identity, store, and snapshots

`pm/fingerprint.xsh` hashes canonical sorted input lines: recipe/package
inputs, proof input, PM tree, core tree, and runner bytes. The plan digest and
artifact/proof keys therefore exclude mtimes, absolute checkout paths, and
`.git` state. A proof-only change changes the proof identity without rebuilding
the payload.

`pm/store.xsh` accepts only validated keys. It locks a key, stages the payload,
verifies its inventory and proof, writes the receipt last, and atomically
renames the final directory. Corrupt final artifacts are rejected rather than
overwritten. `pm/repo.xsh` publishes only those verified plan receipts and
updates a file or remote snapshot index last.

## Root composition

`pm/root.xsh` preflights the exact artifact inventories and ownership before it
mutates a generation root. `pm/generation.xsh` chooses direct runtime roots and
the runtime closure only, then writes the deterministic receipt used by Laputa
to construct a disk image. Build tools do not leak into that closure unless a
separate typed runtime edge requires them.
Regular files and directories retain permission bits through `0o7777`,
including setuid helpers; symlink metadata remains fixed at `0o777`.

## Scope

PM currently supports the aarch64 Linux-musl target only. The shell-compatible
surface is limited to packages whose declared runtime capability requires it;
package construction itself uses typed XSH process and filesystem boundaries.

## Verification

PM behavior is covered by the focused modules under `tests/xsh/`:
`pm_recipe.xsh`, `pm_graph.xsh`, `pm_plan.xsh`, `pm_store.xsh`,
`pm_root.xsh`, `pm_execute.xsh`, `pm_publish.xsh`, `pm_generation.xsh`, and
`pm_cli.xsh`.

Run a host-native suite with `make test-native XSH_ROOT=$HOME/d/laputa-systems/xsh`.
The Docker-backed suite is `make test`.
Use `make test-local-linux` to test the checked-out XSH ARM64 debug binaries in
the pinned Linux test image before updating the published release pin.
