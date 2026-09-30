##! Checked dynamic hook dispatch without production builds or network access.
use pm.recipe
use pm.types

pure hook_package(dir: Path) -> types.Package {
  {
    dir,
    name: "hook-probe",
    ver: "1",
    rel: "1",
    kind: types.package_payload(),
    deps: [],
    mkdeps_host: [],
    mkdeps_target: [],
    upstream_sources: [],
    filetree: [],
    nostrip: false,
    source_mirror: false,
  }
}

test recipe_hooks_dispatch_each_supported_capability_set [fs, process, env, error] { |ctx|
  let original_cwd = fs.cwd()?
  let capabilities: Map[Str] = {
    filesystem: "fs, error",
    filesystem_environment: "fs, env, error",
    processes_environment: "process, env, error",
    filesystem_processes_environment: "fs, process, env, error",
  }
  for {key: name, value: effects} in capabilities {
    let dir = test.temp_dir(ctx, name: name)?
    let pkg = hook_package(dir)
    fp"${dir}/PKGBUILD.xsh".write(f"""##! Hook capability fixture.
error HookProbe = Reached(message: Str)
## Reports that the preparation hook received its typed source path.
export proc prepare(src: Path) [${effects}] -> Result[Unit] {
  return Err(HookProbe.Reached(src.display()))
}
## Reports that the build hook received its typed destination path.
export proc build(dest: Path) [${effects}] -> Result[Unit] {
  return Err(HookProbe.Reached(dest.display()))
}
""")?
    match recipe.call_prepare(pkg, dir) {
      Ok(_) => test.fail("preparation hook did not execute")?
      Err(problem) => problem.message == dir.display()
    }
    let dest = fp"${dir}/output"
    match recipe.call_build(pkg, dir, dest) {
      Ok(_) => test.fail("build hook did not execute")?
      Err(problem) => problem.message == dest.display()
    }
    fs.cwd()? == original_cwd
  }
}

test recipe_hooks_preserve_optional_absence_and_required_build_error [fs, process, env, error] { |ctx|
  let dir = test.temp_dir(ctx, name: "absent-hooks")?
  fp"${dir}/PKGBUILD.xsh".write("##! Recipe without hooks.\n## Exposes its name.\nexport let name = \"no-hooks\"\n")?
  let pkg = hook_package(dir)
  recipe.call_prepare(pkg, dir)?
  recipe.call_prepare_sources(pkg, dir)?
  match recipe.call_build(pkg, dir, dir) {
    Ok(_) => test.fail("payload without a build hook unexpectedly built")?
    Err(problem) => problem == types.PmError.PackageContract("hook-probe: payload package lost its build procedure")
  }
  recipe.call_build({...pkg, kind: types.package_meta()}, dir, dir)?
}

test recipe_hooks_reject_incompatible_parameters_results_and_capabilities [fs, process, env, error] { |ctx|
  let incompatible: Map[Str] = {
    parameter: "export proc build(dest: Str) [fs, error] -> Result[Unit] { return Ok() }",
    result: "export proc build(dest: Path) [fs, error] -> Result[Str] { return \"entered\" }",
    capabilities: "export proc build(dest: Path) [fs, process, env, time, error] -> Result[Unit] { return Ok() }",
    export_kind: "export let build = 7",
  }
  for {key: name, value: declaration} in incompatible {
    let dir = test.temp_dir(ctx, name: name)?
    fp"${dir}/PKGBUILD.xsh".write(f"##! Incompatible hook fixture.\n## Exposes an incompatible build hook.\n${declaration}\n")?
    let pkg = hook_package(dir)
    match recipe.call_build(pkg, dir, dir) {
      Ok(_) => test.fail(f"${name}: incompatible build hook executed")?
      Err(problem) => test.error_kind(problem, "schema")?
    }
  }
}

test recipe_source_preparation_keeps_filesystem_contract [fs, process, env, error] { |ctx|
  let dir = test.temp_dir(ctx, name: "source-hook")?
  fp"${dir}/PKGBUILD.xsh".write("""##! Source hook fixture.
## Writes a marker inside the supplied source path.
export proc prepare_sources(src: Path) [fs, error] -> Result[Unit] {
  fp"\${src}/prepared".write("source prepared")?
}
""")?
  recipe.call_prepare_sources(hook_package(dir), dir)?
  fp"${dir}/prepared".read_text()? == "source prepared"
}
