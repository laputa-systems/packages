##! Behavior coverage for the typed package-recipe boundary.
use pm.recipe
use pm.types

pure fixture(name: Str) -> Path {
  fp"tests/xsh/fixtures/${name}"
}

proc expect_contract_rejection(dir: Path, description: Str) [fs, env, error] {
  match recipe.load_package(dir) {
    Ok(_) => test.fail(f"${description}: recipe unexpectedly loaded")?
    Err(error) => test.ok(error.message != "", f"${description}: error has a message")?
  }
}

proc test_recipe_loads_valid_payload_with_relative_skip_checksum() [fs, env, error] {
  let pkg = recipe.load_package(fixture("recipe-valid-payload"))?
  test.eq(pkg.kind, types.Payload)?
  test.eq(pkg.upstream_sources.len(), 1)?
  test.eq(pkg.upstream_sources[0].kind, types.Auto)?
  test.eq(pkg.upstream_sources[0].checksums[0].sha256, "SKIP")?
  test.eq(pkg.filetree[0].kind, types.File)?
}

proc test_recipe_loads_valid_metapackage() [fs, env, error] {
  let pkg = recipe.load_package(fixture("recipe-valid-meta"))?
  test.eq(pkg.kind, types.Meta)?
  test.eq(pkg.filetree, [])?
}

proc test_recipe_selects_target_filetree_variant() [fs, env, error] {
  env {
    XSH_PM_ARCH = "x86_64"
  } {
    let pkg = recipe.load_package(p"repo/musl")?
    let filetree = [entry.path.display() for entry in pkg.filetree].join("\n")
    test.contains(filetree, "usr/lib/ld-musl-x86_64.so.1")?
    test.eq(filetree.contains("usr/lib/ld-musl-aarch64.so.1"), false)?
  } ?
}

proc test_recipe_rejects_invalid_package_name() [fs, env, error] {
  expect_contract_rejection(fixture("recipe-invalid-name"), "invalid package name")?
}

proc test_recipe_rejects_production_directory_name_mismatch(ctx: TestContext) [fs, env, error] {
  let repo_root = test.temp_dir(ctx, name: "recipe-repo")?
  let dir = fp"${repo_root}/repo/recipe-dir-mismatch"
  let _ = fs.copy_tree(fixture("recipe-dir-mismatch"), dir, parents: true, overwrite: true)?
  expect_contract_rejection(dir, "production directory/name mismatch")?
}

proc test_recipe_rejects_duplicate_dependency() [fs, env, error] {
  expect_contract_rejection(fixture("recipe-duplicate-dependency"), "duplicate dependency")?
}

proc test_recipe_rejects_self_dependency() [fs, env, error] {
  expect_contract_rejection(fixture("recipe-self-dependency"), "self dependency")?
}

proc test_recipe_rejects_invalid_source_kind() [fs, env, error] {
  expect_contract_rejection(fixture("recipe-invalid-source-kind"), "invalid source kind")?
}

proc test_recipe_rejects_invalid_file_kind() [fs, env, error] {
  expect_contract_rejection(fixture("recipe-invalid-file-kind"), "invalid file kind")?
}

proc test_recipe_rejects_remote_skip_checksum() [fs, env, error] {
  expect_contract_rejection(fixture("recipe-remote-skip"), "remote SKIP checksum")?
}

proc test_recipe_rejects_absolute_local_skip_checksum() [fs, env, error] {
  expect_contract_rejection(fixture("recipe-absolute-skip"), "absolute local SKIP checksum")?
}

proc test_recipe_rejects_missing_aarch64_checksum() [fs, env, error] {
  expect_contract_rejection(fixture("recipe-missing-aarch64-checksum"), "missing aarch64 checksum")?
}

proc test_recipe_rejects_duplicate_filetree_path() [fs, env, error] {
  expect_contract_rejection(fixture("recipe-duplicate-filetree"), "duplicate filetree path")?
}

proc test_recipe_rejects_absolute_filetree_path() [fs, env, error] {
  expect_contract_rejection(fixture("recipe-absolute-filetree"), "absolute filetree path")?
}

proc test_recipe_rejects_parent_filetree_traversal() [fs, env, error] {
  expect_contract_rejection(fixture("recipe-parent-filetree"), "parent filetree traversal")?
}

proc test_recipe_rejects_payload_without_build() [fs, env, error] {
  expect_contract_rejection(fixture("recipe-payload-no-build"), "payload without build")?
}

proc test_recipe_rejects_payload_without_proof() [fs, env, error] {
  expect_contract_rejection(fixture("recipe-payload-no-proof"), "payload without proof")?
}

proc test_recipe_rejects_metapackage_with_payload_files() [fs, env, error] {
  expect_contract_rejection(fixture("recipe-meta-payload-files"), "metapackage with payload files")?
}

proc test_recipe_loads_every_migrated_production_recipe() [fs, env, error] {
  for entry in fs.children(p"repo")? {
    continue unless entry.kind == "dir"
    let pkg = recipe.load_package(entry.path)?
    test.eq(pkg.name, entry.name)?
  }
}
