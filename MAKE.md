# pm.make Design Notes

`pm.make` should make porting existing GNU Makefile-based packages into xsh
package recipes straightforward. That is the north star. It should not clone GNU
make semantics, but it should give Makefile concepts such as `SRCS`, `OBJS`,
`CFLAGS`, `CPPFLAGS`, `LDFLAGS`, `LDLIBS`, programs, shared libraries, and
static libraries an obvious xsh destination.

The goal is to keep package builds explicit, typed, debuggable, and portable
inside the xsh/PM environment while reducing the friction of translating a
working Makefile.

The current architecture is pointed in the right direction. A `MakeTask` record
plus `run_tasks()` fits xsh better than parsing Makefiles: PM can validate the
task graph, honor depfiles, track command stamps, rewrite native-cross compiler
commands, schedule parallel work, and report failures without inheriting GNU
make's implicit rule machinery.

The weak part is recipe ergonomics. Package recipes should not have to manually
recreate Makefile boilerplate: walking sources, inventing object names,
accumulating task lists, mapping objects back to task names, extracting
pkg-config flags, and grouping objects for link steps. The current helper layer
now covers those common cases, but future helpers should keep pushing in that
same direction: less repeated recipe plumbing, still explicit build graphs.

## Direction

Keep:

- `MakeTask` as the transparent low-level graph unit.
- `run_tasks()` as the scheduler and validator.
- `compile_*_task` and `link_*_task` as explicit primitives.

Avoid:

- GNU make compatibility as a parser/runtime goal.
- Pattern-rule and suffix-rule systems.
- Recursive make semantics.
- Hidden dependency inference that makes recipe behavior hard to inspect.

Add:

- Higher-level helpers that produce ordinary `MakeTask` values.
- More source-directory helpers with stable object naming.
- A general pkg-config helper that works with the active PM build root.

Good helpers should reduce repeated plumbing without hiding important build
decisions. A recipe ported from a Makefile should mostly transcribe source
lists, flags, libraries, target names, and install rules. It should not need to
reimplement the same object naming and task dependency bookkeeping each time.

The first helper layer exists now: `compile_c_tasks`, `compile_lo_tasks`, and
`compile_cxx_tasks` compile explicit source lists into stable object names and
return `tasks`, `objects`, and `deps`. `task_deps` derives link dependencies
from selected task outputs. These helpers should stay transparent and
composable.

The target-oriented layer now exists: `c_program`, `c_shared_library`,
`c_static_library`, and `c_multi_program` look like direct translations of
simple Makefile targets while still returning explicit `tasks`, `objects`,
`deps`, and `output` data.
`discover_sources`, `pkg_config_flags`, and `install_header_tree` cover common
Makefile porting boilerplate without changing that explicit graph shape.

## Test For Success

The first architectural test is whether packages with existing GNU Makefiles
become straightforward ports. `samurai`, `pkgconf`, `libnl3`, `wpa_supplicant`,
`tmux`, `flex`, `dropbear`, and `mdevd` should become shorter and clearer
without becoming magical. If a helper only moves complexity out of sight, it is
not an improvement. If it returns explicit `tasks`, `objects`, `deps`, and
`output` data that the recipe can inspect and compose, it is likely the right
shape.

See `PM-MAKE-TODO.md` for the concrete follow-up work.
