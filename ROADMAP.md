# Package Manager Roadmap

## Goal

Make `pm.xsh` and `pm/` easier to refactor without losing confidence in package
manager behavior. The next major cleanup should wait until tests can show which
PM paths are actually exercised.

## Current Coverage State

`xsht test --cov` now reports XSH source line/proc coverage from execution
traces, alongside the existing standard API coverage. That is the right
foundation for PM refactoring, but the baseline is still young and the PM suite
needs cleanup before it can drive a broad split safely.

Open coverage questions:

- Which procs in `pm.xsh` and `pm/*.xsh` were executed?
- Which files and line ranges are untouched by the package test suite?
- Which CLI flows cover world planning, install/upgrade, source mirroring,
  metadata sidecars, proof execution, and upload staging?
- Which tests are responsible for covering a risky PM behavior?

Current Linux baseline with local `xsht`:

- Full `tests/xsh/pm.xsh`: 849/4173 lines (20.3%), 121/257 procs (47.0%).

The lowest-covered PM source files are currently `pm/types.xsh`, `pm/make.xsh`,
`pm/sources.xsh`, `pm/remote.xsh`, `pm/util.xsh`, `pm/local.xsh`, and
`pm/extensions.xsh`.

## Phase 1: XSH Source Coverage In `xsht` (Done)

`xsht test --cov` reports source coverage for XSH scripts, not only standard API
coverage.

Implemented behavior:

- `xsht test --cov` runs tests with trace collection enabled automatically.
- The final report includes per-file coverage for loaded `.xsh` files.
- The report includes proc/pure coverage.
- The report includes executable source line coverage where trace spans are
  available.
- The report is scoped to project files and excludes tests, examples, and
  packaged repo fixtures by default.
- `--cov-json FILE` writes structured source/API coverage data for later trend
  tracking and CI gates.

## Phase 2: Package Test Coverage Baseline

Once source coverage exists, establish a baseline for this repo.

Targets:

- [x] `make test` runs `xsht test --cov --cov-json target/coverage/pm.json`.
- [x] Document how to inspect uncovered PM paths locally.
- [x] Capture a baseline coverage report before refactoring.
- [x] Identify the largest uncovered PM areas by behavior, not just by file.

Inspect coverage locally with:

```sh
make test
```

Then open `target/coverage/pm.json`. The `source_coverage` array reports
covered lines and procs per loaded PM source file; sort it by line or proc
coverage to find the next broad behavior gap.

Important PM behaviors to measure:

- Package loading and dependency ordering.
- Local build and proof execution.
- Remote install from tarball and metadata sidecar.
- Source download, checksum update, and mirror staging.
- World planning, rel propagation, and rebuild explanations.
- World build staging, unchanged-metadata reuse, and resumable state.
- Upload and index mutation paths, using fake/local remotes where possible.

## Phase 3: Increase PM Coverage

Add focused tests before moving code around.

Priorities:

- [x] Planning behavior coverage through `world-plan` fixtures: dependency
  tranches, rel bump decisions, carried planned rels, and rebuild reason output.
- [x] Fixture-based tests for remote metadata sidecar consumption.
- [x] Fixture-based tests for world state resume and carried planned rels.
- [x] Failure-path tests for dirty filesystem detection, checksum mismatch,
  missing deps, invalid sidecars, missing proofs, missing service definitions,
  incomplete world stages, and staged artifact verification.
- [x] Minimal integration coverage for build/proof output through local package
  builds and world-plan build fixtures.

The scratch `make test` path is wired to coverage and prefers the local sibling
XSH Linux build, falling back to the published XSH release only when the local
build is unavailable.

Keep tests behavior-oriented. Do not add tests only to raise a percentage if the
behavior is not important.

## Phase 4: PM Refactor

After coverage improves, split the PM implementation around stable behavior
boundaries.

Likely extraction seams:

- World planning and explanation formatting.
- World build state and staging.
- Remote install/index/sidecar handling.
- Local build/proof execution.
- Source fetching and mirroring.
- CLI parsing and command dispatch.

Refactor rule:

- Move behavior behind existing tests first.
- Keep CLI output changes intentional and covered.
- Avoid broad rewrites that combine behavior changes with file movement.
