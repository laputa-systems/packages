# Package-side Laputa boundary

The `packages` repository owns the typed package manager and the package
definitions used by Laputa. It is responsible for recipe validation, catalog
and dependency resolution, exact build/proof identities, immutable artifact
storage, runtime root composition, and verified repository snapshots.

The sibling `laputa` repository owns the integration boundary: the
`qemu-dwl-foot` profile, Docker execution adapter, disk-image construction,
and QEMU/QMP proof. It consumes saved PM `BuildPlan` and generation receipts;
it does not resolve package closures or install a mutable package world.

The boundary is intentionally narrow:

- package recipes declare typed package kind, files, sources, dependencies,
  and a payload build/proof contract;
- `pm repo plan` produces the only package-resolution result;
- `pm repo build` creates or verifies immutable artifacts;
- `pm root compose` creates a verified runtime-only generation;
- Laputa passes profile roots and output locations into that contract and uses
  the resulting generation, kernel manifest, and image artifacts.

Both sides are aarch64 Linux-musl only. A package build may use declared host
or target build dependencies, but those tools do not become runtime content
without an explicit runtime edge. See `PM.md` for the package contract and
the sibling `laputa/docs/DEVELOPMENT.md` for profile commands.
