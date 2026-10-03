##! Behavior coverage for typed package payload boundaries in the prepared builder.
use pm.build
use pm.local
use pm.recipe

pure fixture(name: Str) -> Path {
  fp"tests/xsh/fixtures/${name}"
}

## Builds write a runner and trace beside the recipe, so build a copy instead of the checkout fixture.
proc staged_fixture(workspace: Path, name: Str) [fs, error] -> Result[Path] {
  let pkg_dir = fp"${workspace}/recipes/${name}"
  let _ = fs.copy_tree(fixture(name), pkg_dir, parents: true, overwrite: true)?
  pkg_dir
}

test test_build_prepared_metapackage_has_no_payload_or_package_database [fs, process, env, error] { |ctx|
  let workspace = test.temp_dir(ctx, name: "prepared-meta")?
  let pkg_dir = staged_fixture(workspace, "recipe-valid-meta")?
  let dest = fp"${workspace}/dest"
  let payload = fp"${workspace}/payload.tar.gz"
  build.build_prepared_package(pkg_dir, workspace, dest, payload)?
  let pkg = recipe.load_package(pkg_dir)?
  let built = local.load_built_package_from_dest(pkg, "recipe-valid-meta-1.0.0-1", payload, dest)?

  test.eq(built.manifest, [])?
  test.eq(built.metadata_files, [])?
  test.eq(fs.exists(fp"${dest}/var/lib/xsh-pm/packages/recipe-valid-meta")?, false)?
  test.eq(payload.read_text()?, "laputa metapackage payload marker\n")?
}

test test_build_prepared_archives_every_empty_directory_recorded_in_metadata [fs, process, env, error] { |ctx|
  let workspace = test.temp_dir(ctx, name: "prepared-empty-parent")?
  let pkg_dir = staged_fixture(workspace, "recipe-empty-parent")?
  let dest = fp"${workspace}/dest"
  let payload = fp"${workspace}/payload.tar.gz"
  let extracted = fp"${workspace}/extracted"
  build.build_prepared_package(pkg_dir, workspace, dest, payload)?
  let pkg = recipe.load_package(pkg_dir)?
  let built = local.load_built_package_from_dest(pkg, "recipe-empty-parent-1.0.0-1", payload, dest)?

  test.ok("usr/share" in [entry.path for entry in built.metadata_files])?
  archive.tar_extract(payload, extracted)?
  test.eq(fs.metadata(fp"${extracted}/usr/share")?.kind, "dir")?
}
