# pm/make.xsh TODO

`pm.make` is the small task executor used by package recipes that need a
self-hosted replacement for GNU make. It already handles explicit task
dependencies, depfiles, stale-command detection, cycle checks, duplicate output
validation, and parallel scheduling. The remaining work is mostly about recipe
ergonomics and build-environment contracts, not the scheduler core.

## Source And Task Ergonomics

- Add source-list helpers for common C/C++ package shapes.

  Recipes still hand-roll loops over source files, object naming, and task
  collection. A helper should compile a list of source paths into a stable
  directory-aware object layout, avoiding collisions such as
  `src/utils/config.c` and `wpa_supplicant/config.c`.

  Candidate API:

  ```xsh
  make.compile_c_tasks(cc, triple, cflags, defs, includes, sources, out_dir)
  make.compile_lo_tasks(cc, triple, cflags, defs, includes, sources, out_dir)
  make.compile_cxx_tasks(cc, triple, cflags, defs, includes, sources, out_dir)
  ```

  Return a record with `tasks`, `objects`, and `deps` so link tasks can consume
  it directly.

- Add optional directory discovery on top of the explicit-list helpers.

  A convenience wrapper can walk a source tree and compile matching `.c`,
  `.cc`, `.cpp`, or `.cxx` files. This should remain opt-in; many upstreams
  contain platform-specific files that must not be compiled just because they
  exist.

  Candidate API:

  ```xsh
  make.discover_sources(root, extensions, exclude)
  make.compile_c_dir(cc, triple, cflags, defs, includes, src_dir, out_dir)
  ```

- Add a small dependency helper for custom task sets.

  Recipes that create tasks manually still often need "deps for these object
  outputs." That should not require repeated comprehensions in every recipe.

  Candidate API:

  ```xsh
  make.task_deps(tasks, outputs)
  ```

## Build Flag Discovery

- Add a general pkg-config helper outside `pm.meson`.

  `pm.meson.pkg_config_env()` configures pkg-config for Meson-style builds, but
  handwritten `pm.make` recipes still duplicate flag extraction. A make-level
  helper should return `cflags` and `ldflags` for one or more `.pc` packages
  using the active `LAPUTA_ROOT` sysroot.

  Candidate API:

  ```xsh
  make.pkg_config_flags(packages)
  ```

- Define the build contract for dependency-provided flags.

  Package-level `mkdeps` should ensure dependencies are installed in the build
  root, but it should not blindly translate every dependency into `-l` flags.
  The better contract is:

  - packages that expose compiler/linker flags install `.pc` files;
  - recipes ask for the flags they need via pkg-config;
  - PM ensures pkg-config sees the build root consistently.

  This keeps link inputs explicit while avoiding hardcoded include and library
  paths in recipes such as `wpa_supplicant`.

- Consider a generic header-install helper.

  Several recipes copy public headers by walking a source directory and
  preserving relative paths. A helper would reduce boilerplate, but it should
  support excludes for templates and generated headers.

  Candidate API:

  ```xsh
  make.install_headers(src_dir, dest_dir, exclude)
  ```

## PM Workflow Gaps

- Fix and test multi-package `build-set` with local build dependencies.

  `build-set` should build local packages in dependency order, stage each built
  package into the local repo, and make it available to later packages in the
  same invocation. The current implementation initializes `built_names` but
  does not update it as packages are staged, so local dependencies can still be
  rejected as "has not been built yet."

- Merge primary and public remote indexes for local iteration.

  `refresh_remote_index` currently prefers the public repo when configured and
  falls back to the primary repo. Local packages built into a `file://` primary
  repo should be visible without manually merging indexes. The desired behavior
  is to load both indexes when both are configured, with primary entries taking
  precedence over public entries for the same package/arch.
