##! XSH module `PKGBUILD` package and build operations.
## Package recipe export.
export let name = "laputa-pm"

## Explicit payload or metapackage classification.
export let package_kind = "payload"

## Exported declaration `ver`.
export let ver = "1"

## Exported declaration `rel`.
export let rel = "12"

## Exported declaration `deps`.
export let deps = ["xsh"]

## Exported declaration `mkdeps_host`.
export let mkdeps_host = []

## Exported declaration `upstream_sources`.
export let upstream_sources = [
  {
    source: ../../pm.xsh,
    kind: "auto",
    architectures: ["all"],
    checksums: [{arch: "all", sha256: "SKIP"}],
  },
  {
    source: p"../../pm => pm",
    kind: "auto",
    architectures: ["all"],
    checksums: [{arch: "all", sha256: "SKIP"}],
  },
]

## Exported declaration `filetree`.
export let filetree = [
  {path: p"usr/bin/pm", kind: "file"},
  {path: p"usr/lib/pm/pm.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/build.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/catalog.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/cli.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/configure.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/elfdeps.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/env.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/execute.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/fingerprint.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/generation.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/graph.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/local.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/make.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/meson.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/plan.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/plan_json.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/policy.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/proof.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/recipe.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/remote.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/repo.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/root.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/sources.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/store.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/target.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/types.xsh", kind: "file"},
  {path: p"usr/lib/pm/pm/util.xsh", kind: "file"},
]

## Exported declaration `build`.
export proc build(dest: Path) [fs, error] {
  fs.install(p"pm.xsh", fp"${dest}/usr/lib/pm/pm.xsh", 0o644, parents: true, overwrite: true)?
  let _ = fs.copy_tree(p"pm", fp"${dest}/usr/lib/pm/pm", parents: true, overwrite: true)?
  fs.mkdir(fp"${dest}/usr/bin")?

  fs.write(
    fp"${dest}/usr/bin/pm",
    """#!/bin/xsh
error WrapperError = Failed(message: Str)

proc main(...argv: List[Str]) [process, env, error] {
  let forwarded = ["/bin/xsh", "/usr/lib/pm/pm.xsh", "--"].extend(argv)
  let status = process.run(
    process.command_argv(
      /bin/xsh,
      forwarded,
      /,
      {XSH_MODULE_PATH: "/usr/lib/pm"},
    ),
  )?

  if ! status.ok {
    if status.exited() {
      abort(status.exit_code()?)
    }

    return Err(WrapperError.Failed("pm command was signaled"))
  }
}

main(@args)?
""",
  )?
  fs.chmod(fp"${dest}/usr/bin/pm", 0o755)?
}
