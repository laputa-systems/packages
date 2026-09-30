##! Behavior coverage for the typed package-recipe boundary.
use pm.recipe
use pm.sources
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

proc assert_local_source_checksums(package: Str) [fs, env, error] {
  let package_dir = Path(f"repo/${package}")
  let pkg = recipe.load_package(package_dir)?

  for source in pkg.upstream_sources {
    let raw = source.source.display()
    continue unless raw.starts_with("files/")
    let staged = Path(f"repo/${package}/${raw}")
    let expected = sources.source_checksum(source, "aarch64")?
    test.eq(hash.sha256(staged)?.hex(), expected)?
  }
}

test test_recipe_loads_valid_payload_with_relative_skip_checksum [fs, env, error] {
  let pkg = recipe.load_package(fixture("recipe-valid-payload"))?
  test.eq(pkg.kind, types.Payload)?
  test.eq(pkg.upstream_sources.len(), 1)?
  test.eq(pkg.upstream_sources[0].kind, types.Auto)?
  test.eq(pkg.upstream_sources[0].checksums[0].sha256, "SKIP")?
  test.eq(pkg.filetree[0].kind, types.File)?
}

test test_recipe_loads_valid_metapackage [fs, env, error] {
  let pkg = recipe.load_package(fixture("recipe-valid-meta"))?
  test.eq(pkg.kind, types.Meta)?
  test.eq(pkg.filetree, [])?
}

test test_recipe_loads_linux_metadata_without_kbuild_dynamic_import [fs, env, error] {
  let pkg = recipe.load_package(p"repo/linux")?
  test.eq(pkg.name, "linux")?
  test.eq(pkg.ver, "7.0.5")?
  test.eq(pkg.kind, types.Payload)?
}

test test_ca_certificates_local_sources_match_declared_checksums [fs, env, error] {
  assert_local_source_checksums("ca-certificates")?
}

test test_bison_local_source_matches_declared_checksum [fs, env, error] {
  assert_local_source_checksums("bison")?
}

test test_flex_local_source_matches_declared_checksum [fs, env, error] {
  assert_local_source_checksums("flex")?
}

test test_recipe_selects_target_filetree_variant [fs, env, error] {
  let x86 = recipe.load_package_for_target(p"repo/musl", types.target_x86_64())?
  let arm = recipe.load_package_for_target(p"repo/musl", types.target_aarch64())?
  let x86_filetree = [entry.path.display() for entry in x86.filetree].join("\n")
  let arm_filetree = [entry.path.display() for entry in arm.filetree].join("\n")
  "usr/lib/ld-musl-x86_64.so.1" in x86_filetree
  "usr/lib/ld-musl-aarch64.so.1" not in x86_filetree
  "usr/lib/ld-musl-aarch64.so.1" in arm_filetree
}

test test_recipe_rejects_invalid_package_name [fs, env, error] {
  expect_contract_rejection(fixture("recipe-invalid-name"), "invalid package name")?
}

test test_recipe_rejects_production_directory_name_mismatch [fs, env, error] { |ctx|
  let repo_root = test.temp_dir(ctx, name: "recipe-repo")?
  let dir = fp"${repo_root}/repo/recipe-dir-mismatch"
  let _ = fs.copy_tree(fixture("recipe-dir-mismatch"), dir, parents: true, overwrite: true)?
  expect_contract_rejection(dir, "production directory/name mismatch")?
}

test test_recipe_rejects_duplicate_dependency [fs, env, error] {
  expect_contract_rejection(fixture("recipe-duplicate-dependency"), "duplicate dependency")?
}

test test_recipe_rejects_self_dependency [fs, env, error] {
  expect_contract_rejection(fixture("recipe-self-dependency"), "self dependency")?
}

test test_recipe_rejects_invalid_source_kind [fs, env, error] {
  expect_contract_rejection(fixture("recipe-invalid-source-kind"), "invalid source kind")?
}

test test_recipe_rejects_invalid_file_kind [fs, env, error] {
  expect_contract_rejection(fixture("recipe-invalid-file-kind"), "invalid file kind")?
}

test test_recipe_rejects_remote_skip_checksum [fs, env, error] {
  expect_contract_rejection(fixture("recipe-remote-skip"), "remote SKIP checksum")?
}

test test_recipe_rejects_absolute_local_skip_checksum [fs, env, error] {
  expect_contract_rejection(fixture("recipe-absolute-skip"), "absolute local SKIP checksum")?
}

test test_recipe_rejects_missing_aarch64_checksum [fs, env, error] {
  expect_contract_rejection(fixture("recipe-missing-aarch64-checksum"), "missing aarch64 checksum")?
}

test test_recipe_rejects_duplicate_filetree_path [fs, env, error] {
  expect_contract_rejection(fixture("recipe-duplicate-filetree"), "duplicate filetree path")?
}

test test_recipe_rejects_absolute_filetree_path [fs, env, error] {
  expect_contract_rejection(fixture("recipe-absolute-filetree"), "absolute filetree path")?
}

test test_recipe_rejects_parent_filetree_traversal [fs, env, error] {
  expect_contract_rejection(fixture("recipe-parent-filetree"), "parent filetree traversal")?
}

test test_recipe_rejects_payload_without_build [fs, env, error] {
  expect_contract_rejection(fixture("recipe-payload-no-build"), "payload without build")?
}

test test_recipe_rejects_payload_without_proof [fs, env, error] {
  expect_contract_rejection(fixture("recipe-payload-no-proof"), "payload without proof")?
}

test test_recipe_rejects_metapackage_with_payload_files [fs, env, error] {
  expect_contract_rejection(fixture("recipe-meta-payload-files"), "metapackage with payload files")?
}

test test_recipe_loads_every_migrated_production_recipe [fs, env, error] {
  for entry in fs.children(p"repo")? {
    continue unless entry.kind == "dir"
    let pkg = recipe.load_package(entry.path)?
    test.eq(pkg.name, entry.name)?
  }
}

test test_cargo_proof_accepts_rust_std_at_declared_lib_path [fs, process, env, error] { |ctx|
  if system.uname()?.sysname != "Linux" {
    test.skip("cargo's ELF proof runs in the pinned Linux build environment")
    return
  }

  let root = test.temp_dir(ctx, name: "cargo-proof-root")?
  let xsh = process.which("xsh")?
  fs.install(xsh, fp"${root}/usr/bin/cargo", 0o755, parents: true, overwrite: true)?
  fs.install(xsh, fp"${root}/usr/bin/rustc", 0o755, parents: true, overwrite: true)?
  fs.mkdir(fp"${root}/usr/lib/rustlib/aarch64-unknown-linux-musl/lib")?
  let stderr_path = test.temp_path(ctx, name: "cargo-proof-stderr")
  let status = process.run(
    process.command_argv(
      xsh,
      ["xsh", "repo/cargo/proof.xsh", "--", root.display()],
      fs.cwd()?,
      {XSH_PM_BUILD_ARCH: "x86_64", XSH_PM_TARGET_ARCH: "aarch64"},
      stderr: stderr_path,
    ),
  )?
  test.ok(status.ok, fs.read_text(stderr_path)?)?
}

test test_wpa_proof_runs_binary_with_composed_libraries [fs, process, env, error] { |ctx|
  if system.uname()?.sysname != "Linux" {
    test.skip("the WPA proof runs a Linux executable")
    return
  }

  let root = test.temp_dir(ctx, name: "wpa-proof-root")?
  let xsh = process.which("xsh")?
  let bin = fp"${root}/usr/bin/wpa_supplicant"
  fs.mkdir(fp"${root}/usr/bin", parents: true)?
  fs.mkdir(fp"${root}/usr/lib/xinit/services", parents: true)?
  fs.mkdir(fp"${root}/etc/wpa_supplicant", parents: true)?
  fs.mkdir(fp"${root}/var/lib/xsh-pm/packages/wpa_supplicant", parents: true)?
  fs.write(
    bin,
    f"""#!${xsh.display()}
proc main(...argv: List[Str]) [env, error] {
  if ! (env.get("LD_LIBRARY_PATH") ?? "").starts_with("${root}/usr/lib") {
    abort(3)
  }
}
main(@args)?
""",
  )?
  fs.chmod(bin, 0o755)?
  fs.write(fp"${root}/usr/bin/wpa_cli", "")?
  fs.write(fp"${root}/usr/bin/wpa_passphrase", "")?
  fs.write(fp"${root}/usr/lib/xinit/services/wpa_supplicant.xsh", "")?
  fs.write(fp"${root}/etc/wpa_supplicant/wpa_supplicant.conf", "")?
  fs.write(fp"${root}/var/lib/xsh-pm/packages/wpa_supplicant/metadata.json", "{}")?
  let stderr_path = test.temp_path(ctx, name: "wpa-proof-stderr")
  let status = process.run(
    process.command_argv(xsh, ["xsh", "repo/wpa_supplicant/proof.xsh", "--", root.display()], fs.cwd()?, {}, stderr: stderr_path),
  )?
  test.ok(status.ok, fs.read_text(stderr_path)?)?
}
