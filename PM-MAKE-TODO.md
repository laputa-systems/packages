# pm/make.xsh TODO

`pm.make` is the small task executor used by package recipes that need a
self-hosted replacement for GNU make. It already handles explicit task
dependencies, depfiles, stale-command detection, cycle checks, duplicate output
validation, and parallel scheduling. The remaining work is mostly about recipe
ergonomics and build-environment contracts, not the scheduler core.

## Source And Task Ergonomics

- Consider directory compile wrappers on top of `discover_sources`.

  `make.discover_sources(root, extensions, exclude)` now covers explicit
  source discovery. A later wrapper could combine discovery with
  `compile_c_tasks`, but this should remain opt-in; many upstreams contain
  platform-specific files that must not be compiled just because they exist.

  Candidate API:

  ```xsh
  make.compile_c_dir(cc, triple, cflags, defs, includes, src_dir, out_dir)
  ```

## Build Flag Discovery

- Define the build contract for dependency-provided flags.

  Package-level `mkdeps` should ensure dependencies are installed in the build
  root, but it should not blindly translate every dependency into `-l` flags.
  The better contract is:

  - packages that expose compiler/linker flags install `.pc` files;
  - recipes ask for the flags they need via pkg-config;
  - PM ensures pkg-config sees the build root consistently.

  This keeps link inputs explicit while avoiding hardcoded include and library
  paths in recipes. `make.pkg_config_flags(packages)` now provides the package
  recipe side of this contract; the remaining work is documenting and enforcing
  package `.pc` expectations consistently.
