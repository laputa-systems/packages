##! Behavior coverage for exact package and executor semantic fingerprints.
use pm.fingerprint
use pm.recipe
use pm.types

pure fixture(name: Str) -> Path {
  fp"tests/xsh/fixtures/${name}"
}

proc copied_package(ctx: TestContext, name: Str) [fs, env, error] -> Result[types.Package] {
  let dir = test.temp_dir(ctx, name: name)?
  let _ = fs.copy_tree(fixture("fingerprint-package"), dir, parents: true, overwrite: true)?
  recipe.load_package(dir)?
}

proc copied_executor(ctx: TestContext) [fs, error] -> Result[Path] {
  let root = test.temp_dir(ctx, name: "fingerprint-executor")?
  let _ = fs.copy_tree(fixture("fingerprint-executor"), root, parents: true, overwrite: true)?
  root
}

proc build_input(pkg: types.Package) [fs, error] -> Result[Str] {
  fingerprint.package_build_input(p".", pkg, types.Aarch64LinuxMusl)?
}

proc test_package_build_fingerprint_is_repeatable_and_ignores_mtime(ctx: TestContext) [fs, env, error] {
  let pkg = copied_package(ctx, "fingerprint-repeat")?
  let first = build_input(pkg)?
  test.eq(build_input(pkg)?, first)?
  let helper = fp"${pkg.dir}/helper.xsh"
  fs.write(helper, helper.read_text()?)?
  test.eq(build_input(pkg)?, first)?
}

proc test_package_build_fingerprint_changes_for_pkgbuild(ctx: TestContext) [fs, env, error] {
  let pkg = copied_package(ctx, "fingerprint-pkgbuild")?
  let first = build_input(pkg)?
  let pkgbuild = fp"${pkg.dir}/PKGBUILD.xsh"
  fs.write(pkgbuild, pkgbuild.read_text()?.replace("1.0.0", "1.0.1"))?
  test.eq(build_input(pkg)? == first, false)?
}

proc test_package_build_fingerprint_changes_for_helper_module(ctx: TestContext) [fs, env, error] {
  let pkg = copied_package(ctx, "fingerprint-helper")?
  let first = build_input(pkg)?
  fs.write(fp"${pkg.dir}/helper.xsh", "changed helper\n")?
  test.eq(build_input(pkg)? == first, false)?
}

proc test_package_build_fingerprint_changes_for_files_tree(ctx: TestContext) [fs, env, error] {
  let pkg = copied_package(ctx, "fingerprint-files")?
  let first = build_input(pkg)?
  fs.write(fp"${pkg.dir}/files/input.txt", "changed input\n")?
  test.eq(build_input(pkg)? == first, false)?
}

proc test_package_build_fingerprint_changes_for_service(ctx: TestContext) [fs, env, error] {
  let pkg = copied_package(ctx, "fingerprint-service")?
  let first = build_input(pkg)?
  fs.write(fp"${pkg.dir}/service.xsh", "changed service\n")?
  test.eq(build_input(pkg)? == first, false)?
}

proc test_proof_fingerprint_is_independent_from_build_input(ctx: TestContext) [fs, env, error] {
  let pkg = copied_package(ctx, "fingerprint-proof")?
  let build_before = build_input(pkg)?
  let proof_before = fingerprint.package_proof_input(p".", pkg)?
  fs.write(fp"${pkg.dir}/proof.xsh", "changed proof\n")?
  test.eq(build_input(pkg)?, build_before)?
  test.eq(fingerprint.package_proof_input(p".", pkg)? == proof_before, false)?
}

proc test_pm_tree_fingerprint_changes_for_implementation(ctx: TestContext) [fs, error] {
  let root = copied_executor(ctx)?
  let first = fingerprint.pm_tree(root)?
  fs.write(fp"${root}/pm/build.xsh", "changed implementation\n")?
  test.eq(fingerprint.pm_tree(root)? == first, false)?
}

proc test_core_tree_fingerprint_changes_for_applet(ctx: TestContext) [fs, error] {
  let root = copied_executor(ctx)?
  let first = fingerprint.core_tree(fp"${root}/core")?
  fs.write(fp"${root}/core/applet.xsh", "changed applet\n")?
  test.eq(fingerprint.core_tree(fp"${root}/core")? == first, false)?
}

proc test_runner_fingerprint_changes_for_runner_bytes(ctx: TestContext) [fs, error] {
  let root = copied_executor(ctx)?
  let runners = fp"${root}/runners"
  let first = fingerprint.runners(fp"${runners}/xsh", fp"${runners}/xshi", fp"${runners}/xsht")?
  fs.write(fp"${runners}/xshi", "changed xshi\n")?
  test.eq(fingerprint.runners(fp"${runners}/xsh", fp"${runners}/xshi", fp"${runners}/xsht")? == first, false)?
}

proc test_package_fingerprint_ignores_absolute_checkout_path(ctx: TestContext) [fs, env, error] {
  let first = copied_package(ctx, "fingerprint-checkout-a")?
  let second = copied_package(ctx, "fingerprint-checkout-b")?
  test.eq(build_input(first)?, build_input(second)?)
}
