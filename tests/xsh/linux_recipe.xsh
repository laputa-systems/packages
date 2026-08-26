##! Regression coverage for Linux recipe modules that must parse under the published runner.
use pm.fingerprint
use pm.build as pm_build
use pm.catalog
use pm.plan
use pm.policy
use pm.recipe
use pm.sources
use pm.types
use pm.util
use repo.linux.linux_config
use repo.linux.PKGBUILD-shared as linux_shared

pure fixture(name: Str) -> Path {
  fp"tests/xsh/fixtures/linux-recipe/${name}"
}

proc runner() [fs, process, env, error] -> Result[Path] {
  let configured = (env.get("XSH_HOST") ?? "").trim()

  if configured != "" {
    return path.absolute(fp"${configured}")?
  }

  process.which("xsh")?
}

proc module_root() [fs, error] -> Result[Path] {
  path.absolute(p".")?
}

proc linux_config_source(pkg: types.Package) [error] -> Result[types.UpstreamSource] {
  for source in pkg.upstream_sources {
    if source.source.display().starts_with("files/config/aarch64/") {
      return source
    }
  }

  return Err(types.PmError.PackageContract("linux is missing its aarch64 config input"))
}

proc test_linux_kbuild_modules_parse_and_preserve_job_error_branch(ctx: TestContext) [fs, process, env, error] {
  let stderr = test.temp_path(ctx, name: "linux-kbuild-jobs.err")
  let xsh = runner()?
  let modules = module_root()?
  let script = fixture("published-runner-shared.xsh")
  let success = run.status XSH_MODULE_PATH=$modules XSH_LINUX_KBUILD_JOBS="1" $xsh $script 2> $stderr ?
  test.ok(success.ok)?
  let failure = run.status XSH_MODULE_PATH=$modules XSH_LINUX_KBUILD_JOBS="0" $xsh $script 2> $stderr ?
  test.eq(failure.ok, false)?
  test.contains(stderr.read_text()?, "linux-kbuild-jobs")?
}

proc test_linux_config_fragment_is_explicit_staged_fingerprinted_input(ctx: TestContext) [fs, net, process, env, time, error] {
  let original = recipe.load_package(p"repo/linux")?
  let config = linux_config_source(original)?
  let stage_root = test.temp_dir(ctx, name: "linux-config-stage")?
  let source = fp"${stage_root}/source"
  fs.mkdir(source)?
  sources.stage_package_sources(stage_root, {...original, upstream_sources: [config]}, source, true)?
  let staged = fp"${source}/.laputa-inputs/files/config/aarch64/base-aarch64.fragment"
  test.ok(staged.exists()?)?

  let copied_root = test.temp_dir(ctx, name: "linux-config-fingerprint")?
  let copied = fp"${copied_root}/repo/linux"
  let _ = fs.copy_tree(p"repo/linux", copied, parents: true, overwrite: true)?
  let before = recipe.load_package(copied)?
  let first = fingerprint.package_build_input(copied_root, before, types.target_aarch64())?
  fs.write(fp"${copied}/files/config/aarch64/base-aarch64.fragment", "# changed staged config input\n")?
  let after = recipe.load_package(copied)?
  test.eq(fingerprint.package_build_input(copied_root, after, types.target_aarch64())? == first, false)?
}

proc test_laputa_pm_repository_inputs_stage_and_fingerprint_from_an_isolated_recipe(ctx: TestContext) [fs, net, process, env, time, error] {
  let root = test.temp_dir(ctx, name: "laputa-pm-repository-input")?
  let package_dir = fp"${root}/repo/laputa-pm"
  let source = fp"${root}/source"
  let _ = fs.copy_tree(p"repo/laputa-pm", package_dir, parents: true, overwrite: true)?
  fs.copy(p"pm.xsh", fp"${root}/pm.xsh", overwrite: true)?
  let _ = fs.copy_tree(p"pm", fp"${root}/pm", parents: true, overwrite: true)?
  fs.mkdir(source)?
  let pkg = recipe.load_package(package_dir)?
  let first = fingerprint.package_build_input(root, pkg, types.target_aarch64())?

  env {
    XSH_PM_REPOSITORY_ROOT = root.display()
  } {
    # `pkg.dir` intentionally points at an isolated recipe copy. Repository
    # inputs must still stage from the explicit repository root, not parent
    # traversal from that directory.
    sources.stage_package_sources(root, pkg, source, false)?
  } ?

  test.ok(fs.exists(fp"${source}/pm.xsh")?)?
  test.ok(fs.exists(fp"${source}/pm/execute.xsh")?)?
  fs.write(fp"${root}/pm/execute.xsh", "changed PM executor input\n")?
  let second = fingerprint.package_build_input(root, pkg, types.target_aarch64())?
  test.eq(second == first, false)?
}

proc test_baselayout_directory_input_stages_into_the_prepared_source_root(ctx: TestContext) [fs, net, process, env, time, error] {
  let pkg = recipe.load_package(p"repo/baselayout")?
  let root = test.temp_dir(ctx, name: "baselayout-directory-input")?
  let source = fp"${root}/source"
  fs.mkdir(source)?

  sources.stage_package_sources(root, pkg, source, false)?

  test.ok(fs.exists(fp"${source}/etc/passwd")?)?
  test.ok(fs.exists(fp"${source}/usr/lib/init/rc.boot")?)?
}

proc test_baselayout_declares_boot_mount_directories_as_payload(ctx: TestContext) [fs, env, error] {
  let pkg = recipe.load_package(p"repo/baselayout")?
  let trees = [entry.path.display() for entry in pkg.filetree if entry.kind == types.file_kind_tree()]

  # The kernel mounts devtmpfs before `/init`; the remaining mount points must
  # also be present before rc.boot performs its explicit mounts and fstab pass.
  for required in ["dev", "dev/pts", "dev/shm", "proc", "run", "sys", "tmp"] {
    test.ok(required in trees)?
  }
}

proc test_baselayout_build_materializes_empty_boot_mount_directories(ctx: TestContext) [fs, net, process, env, time, error] {
  let pkg = recipe.load_package(p"repo/baselayout")?
  let root = test.temp_dir(ctx, name: "baselayout-empty-directories")?
  let source = fp"${root}/source"
  let dest = fp"${root}/dest"
  fs.mkdir(source)?
  sources.stage_package_sources(root, pkg, source, false)?
  recipe.call_build(pkg, source, dest)?

  for required in ["dev", "dev/pts", "dev/shm", "proc", "run", "sys", "tmp"] {
    test.eq(fs.metadata(fp"${dest}/${required}")?.kind, "dir")?
  }
}

proc test_baselayout_artifact_archives_empty_boot_mount_directories(ctx: TestContext) [fs, net, process, env, time, error] {
  let root = test.temp_dir(ctx, name: "baselayout-artifact-directories")?
  let recipe_dir = fp"${root}/recipe"
  let source = fp"${root}/source"
  let dest = fp"${root}/dest"
  let archive_path = fp"${root}/baselayout.tar.gz"
  let extracted = fp"${root}/extracted"
  let _ = fs.copy_tree(p"repo/baselayout", recipe_dir, parents: true, overwrite: true)?
  fs.mkdir(source)?
  let pkg = recipe.load_package(recipe_dir)?
  sources.stage_package_sources(root, pkg, source, false)?
  pm_build.build_prepared_package(recipe_dir, source, dest, archive_path)?

  if !fs.exists(fp"${dest}/dev")? {
    test.fail("baselayout prepared payload is missing dev")?
  }

  archive.tar_extract(archive_path, extracted)?

  for required in ["dev", "dev/pts", "dev/shm", "proc", "run", "sys", "tmp"] {
    if !fs.exists(fp"${extracted}/${required}")? {
      test.fail(f"baselayout archive is missing ${required}")?
    }

    test.eq(fs.metadata(fp"${extracted}/${required}")?.kind, "dir")?
  }
}

proc test_xsh_proof_uses_declared_usr_bin_runners_without_baselayout(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "xsh-proof-runtime-closure")?
  let stderr = fp"${root}/xsh-proof.stderr"
  let modules = module_root()?
  let xsh = runner()?
  fs.mkdir(fp"${root}/usr/bin")?
  fs.mkdir(fp"${root}/usr/lib/xsh/core")?
  fs.mkdir(fp"${root}/var/lib/xsh-pm/packages/xsh")?

  for path_value in [
    fp"${root}/usr/bin/sh",
    fp"${root}/usr/bin/xsh",
    fp"${root}/usr/bin/xshi",
    fp"${root}/usr/bin/xsht",
    fp"${root}/usr/bin/cat",
    fp"${root}/usr/bin/ifup",
    fp"${root}/usr/bin/env",
    fp"${root}/usr/lib/xsh/core/cat",
  ] {
    fs.write(path_value, "typed xsh proof fixture\n")?
  }

  fs.write(fp"${root}/var/lib/xsh-pm/packages/xsh/metadata.json", "{}\n")?
  let status = process.run(
    process.command_argv(
      xsh,
      [xsh.display(), "repo/xsh/proof.xsh", "--", root.display()],
      cwd: modules,
      env: {XSH_MODULE_PATH: modules.display()},
      stderr: stderr,
    ),
  )?
  if ! status.ok {
    test.fail(stderr.read_text()?)?
  }
}

proc test_wlroots_declares_the_runtime_seatd_provider(ctx: TestContext) [fs, env, error] {
  let pkg = recipe.load_package(p"repo/wlroots0.19-mesa")?
  test.ok("seatd" in pkg.deps)?
}

proc test_wlroots_plan_carries_seatd_as_a_runtime_edge(ctx: TestContext) [fs, env, error] {
  let catalog_value = catalog.load(p".")?
  let plan_value = plan.resolve(
    catalog_value,
    {target: types.target_aarch64(), index_sha256: "linux-recipe-empty-remote", packages: []},
    policy.aarch64_docker(),
    ["wlroots0.19-mesa"],
    false,
    {format: "laputa-pm-executor-1", pm_sha256: "linux-recipe-pm", xsh_sha256: "linux-recipe-xsh", core_sha256: "linux-recipe-core"},
  )?
  var found = false
  for node in plan_value.nodes {
    continue unless node.name == "wlroots0.19-mesa"
    for dependency in node.dependencies {
      if dependency.name == "seatd" {
        test.eq(dependency.kind, types.dependency_runtime())?
        found = true
      }
    }
  }

  test.ok(found)?
}

proc test_linux_config_resolves_staged_fragment_from_isolated_cwd_and_rejects_missing(ctx: TestContext) [fs, env, error] {
  let root = test.temp_dir(ctx, name: "linux-config-resolve")?
  let source = fp"${root}/source"
  let staged = fp"${source}/.laputa-inputs/files/config/aarch64/base-aarch64.fragment"
  let recipe_root = fp"${root}/recipe"
  let unrelated = fp"${root}/unrelated"
  fs.mkdir(staged.parent)?
  fs.mkdir(recipe_root)?
  fs.mkdir(unrelated)?
  fs.write(staged, "CONFIG_LAPUTA_STAGE=y\n")?

  env {
    XSH_PM_SOURCE_DIR = source.display()
    XSH_PM_RECIPE_DIR = recipe_root.display()
  } {
    cd unrelated {
      let resolved = linux_config.resolve_config_fragments([p"files/config/aarch64/base-aarch64.fragment"])?
      test.eq(resolved, [staged])?
    } ?
  } ?

  fs.remove(staged)?

  env {
    XSH_PM_SOURCE_DIR = source.display()
    XSH_PM_RECIPE_DIR = recipe_root.display()
  } {
    match linux_config.resolve_config_fragments([p"files/config/aarch64/base-aarch64.fragment"]) {
      Ok(_) => test.fail("missing staged Linux config fragment unexpectedly resolved")?
      Err(error) => test.contains(error.message, "missing kernel config fragment files/config/aarch64/base-aarch64.fragment")?
    }
  } ?
}

proc test_bison_parses_linux_kconfig_argv_and_rejects_missing_grammar(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "linux-bison-kconfig")?
  let grammar = fp"${root}/scripts/kconfig/parser.y"
  let output = fp"${root}/scripts/kconfig/parser.tab.c"
  let header = fp"${root}/scripts/kconfig/parser.tab.h"
  let stderr = fp"${root}/bison.err"
  let modules = module_root()?
  let xsh = runner()?
  let bison = fp"${modules}/repo/bison/files/bison.xsh"
  fs.mkdir(grammar.parent)?
  fs.write(
    grammar,
    "%token WORD\n%start input\n%%\ninput: WORD ;\n%%\n",
  )?

  let success = process.run(
    process.command_argv(
      xsh,
      [
        xsh.display(),
        bison.display(),
        "--",
        "-o",
        "scripts/kconfig/parser.tab.c",
        "--defines=scripts/kconfig/parser.tab.h",
        "-t",
        "-l",
        "scripts/kconfig/parser.y",
      ],
      cwd: root,
      env: {XSH_BISON_NO_UPSTREAM: "1"},
      stderr: stderr,
    ),
  )?
  if ! success.ok {
    test.fail(stderr.read_text()?)?
  }
  test.ok(success.ok)?
  test.ok(output.exists()?)?
  test.ok(header.exists()?)?

  let missing = process.run(
    process.command_argv(
      xsh,
      [
        xsh.display(),
        bison.display(),
        "--",
        "-o",
        "scripts/kconfig/parser.tab.c",
        "--defines=scripts/kconfig/parser.tab.h",
        "-t",
        "-l",
        "scripts/kconfig/missing.y",
      ],
      cwd: root,
      env: {XSH_BISON_NO_UPSTREAM: "1"},
      stderr: stderr,
    ),
  )?
  test.eq(missing.ok, false)?
  test.contains(stderr.read_text()?, "No such file or directory")?
}

proc test_flex_parses_linux_kconfig_argv_and_rejects_missing_input(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "linux-flex-kconfig")?
  let lexer = fp"${root}/scripts/kconfig/lexer.l"
  let output = fp"${root}/scripts/kconfig/lexer.lex.c"
  let stderr = fp"${root}/flex.err"
  let modules = module_root()?
  let xsh = runner()?
  let flex = fp"${modules}/repo/flex/files/flex.xsh"
  fs.mkdir(lexer.parent)?
  fs.write(lexer, "%%\n[a-z]+ return 1;\n%%\n")?

  let success = process.run(
    process.command_argv(
      xsh,
      [
        xsh.display(),
        flex.display(),
        "--",
        "-oscripts/kconfig/lexer.lex.c",
        "-L",
        "scripts/kconfig/lexer.l",
      ],
      cwd: root,
      env: {XSH_FLEX_NO_UPSTREAM: "1"},
      stderr: stderr,
    ),
  )?
  if ! success.ok {
    test.fail(stderr.read_text()?)?
  }
  test.ok(output.exists()?)?

  let missing = process.run(
    process.command_argv(
      xsh,
      [
        xsh.display(),
        flex.display(),
        "--",
        "-oscripts/kconfig/lexer.lex.c",
        "-L",
        "scripts/kconfig/missing.l",
      ],
      cwd: root,
      env: {XSH_FLEX_NO_UPSTREAM: "1"},
      stderr: stderr,
    ),
  )?
  test.eq(missing.ok, false)?
  test.contains(stderr.read_text()?, "No such file or directory")?
}

proc test_linux_discovery_pool_executes_worker_from_staged_recipe(ctx: TestContext) [fs, process, env, time, error] {
  let root = test.temp_dir(ctx, name: "linux-staged-discovery-worker")?
  let recipe_root = fp"${root}/recipe"
  let source = fp"${root}/source"
  let worker = fp"${recipe_root}/kbuild-pool-worker.xsh"
  let _ = fs.copy_tree(p"repo/linux", recipe_root, parents: true, overwrite: true)?
  fs.mkdir(source)?
  fs.write(fp"${source}/.config", "")?
  fs.write(fp"${source}/Kbuild", "obj-y += one.o\n")?
  test.ok(worker.exists()?)?

  env {
    XSH_PM_SOURCE_DIR = source.display()
    XSH_PM_RECIPE_DIR = recipe_root.display()
    XSH_LINUX_KBUILD_DISCOVER_JOBS = "1"
  } {
    cd source {
      let plan = linux_shared.discover_package_plan("arm64")?
      test.ok(p"one.o" in plan.objects)?
    } ?
  } ?
}
