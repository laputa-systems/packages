# pm/make.xsh — Improvement Plan

`pm.make` is a task-based build executor that replaces GNU make for Laputa
package builds.  It provides `compile_c_task`, `link_executable_task`,
`run_tasks`, and related helpers.  It works well for packages with a small,
known set of source files (dropbear, samurai, pkgconf, libffi).  For larger
packages like wpa_supplicant (~100 source files) and libnl3 (~20 source files),
several friction points made the build experience painful.

## Friction points (observed during libnl3 + wpa_supplicant builds)

1. **Hardcoded source file lists.**  Every `.c` file must be listed manually in
   the PKGBUILD.  For wpa_supplicant this is ~100 files across 8 source
   directories.  Miss one and you get a linker error.  Add one that needs a
   missing config option and you get a compile error.  The feedback loop is
   slow (Docker build for each iteration).

2. **No glob or directory-based source discovery.**  There is no way to say
   "compile all `.c` files under `src/`".  Each file must be enumerated.

3. **No automatic dependency resolution between tasks.**  When compiling
   `wpa_cli.c`, the linker needs `edit.o` (from `utils/edit.c`).  The
   PKGBUILD author must manually wire these dependencies.  A mistake means
   linker errors.

4. **No `-D` / `-I` flag inheritance from package dependencies.**  libnl3
   installs headers to `/usr/include/netlink/`.  wpa_supplicant needs
   `-I/usr/include` and `-DCONFIG_LIBNL32` to find them.  These must be
   hardcoded in wpa_supplicant's PKGBUILD instead of being discovered through
   pkg-config or a dependency-provided contract.

5. **Duplicate object filenames from different directories.**  `src/utils/config.c`
   and `wpa_supplicant/config.c` both produce `config.o`.  The PKGBUILD must
   manually disambiguate by mangling filenames (`src_utils_config.o`).  A
   directory-aware object layout would avoid this.

6. **No shared library dependency chaining.**  libnl-genl-3.so links against
   libnl-3.so.  This dependency must be expressed manually through linker
   flags.  Package-level `deps`/`mkdeps` don't automatically translate to
   `-l` flags.

7. **Method chaining not supported.**  `path.display().replace("/", "_")`
   is a parse error.  Intermediate `var` assignments are required.  This is
   a language limitation but surfaced repeatedly while building source lists.

8. **No `r"""..."""` (raw string) syntax for triple-quoted strings.**  When
   generating config headers that contain `$` characters (e.g., version
   strings), the PKGBUILD must use `f"""..."""` and carefully avoid unwanted
   interpolation.  Raw triple-quoted strings would eliminate this friction.

## Proposed improvements

### Short term (low effort, high impact)

- **`make.compile_dir(cc, triple, cflags, defs, includes, src_dir, out_dir)`**
  — compiles all `.c` files under `src_dir` into `out_dir`, preserving
  directory structure in object names (`src_utils_config.o`).  Returns the
  list of object paths and task names for linking.  Eliminates hardcoded
  source file lists for most packages.

- **`make.compile_filtered(cc, triple, cflags, defs, includes, files, out_dir)`**
  — like `compile_dir` but takes an explicit file list and automatically
  mangles object names to avoid collisions.  The existing per-file API
  (`compile_c_task`) is preserved for packages with special per-file flags.

- **`make.link_deps(task_names)`** — given a list of task names, returns the
  correct `deps` list for `link_executable_task`.  Eliminates the manual
  `[task.name for task in all_tasks if ...]` pattern.

### Medium term

- **`make.pkg_config(package_name)`** — returns `cflags` and `ldflags` from a
  package's installed `.pc` file.  Would let wpa_supplicant get `-I` and `-l`
  flags from libnl3 automatically.

- **`make.install_headers(src_dir, dest_dir)`** — walks a source directory
  and installs headers to a destination, handling directory creation and
  symlinks.  libnl3's header install loop would be a one-liner.

- **Automatic `mkdep` → `-l` translation.**  If package A declares `mkdeps:
  ["libnl3"]`, the build environment should set `CFLAGS` and `LDFLAGS` so
  that headers and libraries from libnl3 are found without manual `-I`/`-L`
  flags.  This could be done through a `build-env` record passed to
  `build(dest)`.

### Language improvements (xsh)

- **Method chaining on `Str` and `Path`.**  `s.replace("/", "_").replace(".c",
  ".lo")` should work without intermediate variables.

- **Raw triple-quoted strings (`r"""..."""`).**  Needed for embedding C header
  content with literal `$` and `\` characters.

### Build workflow improvements (PM)

- **Multi-package `build-set` with local `mkdeps`.**  When building packages
  A and B together (where B `mkdep`s A), PM should build A, publish it to the
  local repo, and make it available for B's build — all in one `build-set`
  invocation.  Currently this fails with "has not been built yet" due to a
  type error in `missing_world_dependencies`.

- **Merged index from primary + public repos.**  PM's `refresh_remote_index`
  uses only the public repo for its index.  When iterating locally, packages
  built into a `file://` primary repo are invisible unless the index is
  manually merged.  PM should merge indices from both repos, with primary
  taking precedence over public.
