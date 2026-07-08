# Package Manager Roadmap

## Goal

Make `pm.xsh` and `pm/` cleaner, less duplicated, and more idiomatic without
losing confidence in package manager behavior.

With the current PM suite in place, split the PM implementation around stable
behavior boundaries. The goal is cleaner, less duplicated, more idiomatic XSH
code, not line movement for its own sake. Small CLI output cleanups are allowed
when they make the behavior clearer, but output changes should be intentional
and covered by test updates.

Do not require coverage to increase during this refactor. The existing coverage
is a safety net, not a metric target.

### Target Shape

`pm.xsh` should become a thin entrypoint and command router. It may keep
top-level help and coarse command dispatch, but world-build and world-plan logic
should move out of it.

Use a unified `pm/world.xsh` module rather than separate `world_plan.xsh` and
`world_build.xsh`. World planning and world execution share enough state,
fingerprinting, package rel decisions, cache paths, and output vocabulary that a
single module is likely easier to keep coherent.

Likely ownership after the refactor:

- `pm/world.xsh`: world package expansion, dependency/tranche planning, rebuild
  reasons, rel propagation, world cache naming, world state, staged artifact
  verification, tranche build execution, world upload/sync orchestration, and
  world output formatting.
- `pm/cli.xsh`: command parsing, default-context expansion, command usage
  strings, and dispatch helpers that do not belong to a domain module.
- `pm/repo.xsh`: repository build/upload/export flows, staged index mutation,
  source mirror export, and repo artifact verification.
- `pm/install.xsh`: install/remove/update/upgrade flows, package DB mutation,
  manifest ownership, dirty filesystem checks, lifecycle hook integration, and
  remote tarball/metapackage install.
- `pm/build.xsh`: local package build, chroot build, proof execution, build log
  handling, and build cache preservation.
- Existing support modules stay focused: `pm/remote.xsh` for remote transport
  and remote index decoding, `pm/sources.xsh` for source resolution/mirroring,
  `pm/util.xsh` for small shared pure helpers, and `pm/types.xsh` for stable
  shared types.

This target shape is directional. If extraction shows that a boundary creates
awkward APIs or cycles, prefer a cleaner local shape over matching the list
exactly.

### Refactor Sequence

1. Extract world logic into `pm/world.xsh`.

   Start with the low-risk planning helpers currently in `pm.xsh`: dependency
   classification, tranche levels, version/rel comparison, rel planning, rebuild
   reasons, plan printing, world cache key calculation, and world state helpers.
   Keep the public entrypoint shape close to the current `world_plan_repo`
   behavior so existing tests can keep driving the CLI.

2. Move world execution into the same module.

   Move staged root handling, chroot base installation, package staging, world
   state read/write/compatibility, build tranche execution, staged artifact
   verification, and upload/sync behavior. This is where duplicated output
   formatting and elapsed-time reporting should be cleaned up.

3. Extract CLI plumbing.

   Move command usage, default context handling, package-dir detection, and
   dispatch helpers into `pm/cli.xsh`. After this step, `pm.xsh` should mostly
   parse argv, call domain commands, and handle extension fallback.

4. Extract repo workflows.

   Move `build`, `upload`, `build-upload`, and `upload-repo-export` flows into
   `pm/repo.xsh`. Keep source mirror export and staged index mutation together
   so repository artifact shape remains easy to reason about.

5. Split install/build responsibilities.

   Split the current broad `pm/local.xsh` surface only after the world and repo
   flows have moved. Separate package DB/install/remove behavior from build and
   proof execution. The important cleanup here is reducing cross-cutting state
   and duplicated manifest handling, not forcing a perfect taxonomy.

6. Tighten APIs after movement.

   Once behavior is in the right modules, narrow exported APIs, make helper
   names domain-specific, collapse duplicate helpers, and move generic helpers
   out of `pm/util.xsh` unless they are truly shared.

### Guardrails

- Run `make test` after each meaningful extraction step.
- Prefer moving behavior behind existing CLI tests before changing semantics.
- Keep output changes intentional; update tests when improved output is the
  point.
- Do not mix large mechanical moves with behavioral rewrites in the same step.
- Avoid new abstractions unless they remove real duplication or make effectful
  boundaries clearer.
- Keep package-facing helper modules (`pm/make.xsh`, `pm/meson.xsh`,
  `pm/proof.xsh`, `pm/configure.xsh`) stable unless the refactor reveals a real
  package API issue.
