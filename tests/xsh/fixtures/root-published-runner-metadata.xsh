##! Published-runner regression for typed artifact metadata consumed by root preflight.
use pm.root
use pm.store
use pm.types

pure digest(value: Str) -> Str {
  bytes.from_text(value).sha256().hex()
}

proc main() [fs, error] {
  let workspace = p"/tmp/laputa-root-published-metadata"
  fs.remove(workspace, missing_ok: true)?
  defer fs.remove(workspace, missing_ok: true)?
  let stage = fp"${workspace}/stage"
  let contents = fp"${stage}/contents"
  let payload = fp"${stage}/payload.tar.gz"
  let metadata = fp"${stage}/metadata.json"
  let proof = fp"${stage}/proof.json"
  let store_root = fp"${workspace}/store"
  fs.mkdir(fp"${contents}/usr/bin", parents: true)?
  fs.write(fp"${contents}/usr/bin/demo", "published root metadata\n")?
  fs.chmod(fp"${contents}/usr/bin/demo", 0o755)?
  # This is the legacy remote metadata shape: it has an exact payload inventory
  # but predates `package_kind` and its package DB was appended to the archive.
  fs.write(
    metadata,
    json.encode({
      arch: "aarch64",
      name: "demo",
      ver: "1.0.0",
      rel: "1",
      deps: [],
      mkdeps_host: [],
      mkdeps_target: [],
      filetree: [{path: "usr/bin/demo", kind: "file"}],
      manifest: ["usr/bin/demo"],
      metadata_sha256: digest("published metadata files"),
      files: [{
        path: "usr/bin/demo",
        kind: "file",
        mode: 0o755,
        sha256: digest("published root metadata\n"),
        target: "",
      }],
    })? + "\n",
  )?
  let database = fp"${contents}/var/lib/xsh-pm/packages/demo"
  fs.mkdir(database, parents: true)?
  fs.write(fp"${database}/manifest.json", json.encode(["usr/bin/demo"])?)?
  fs.write(fp"${database}/etcsums.json", json.encode([])?)?
  fs.write(
    fp"${database}/metadata.json",
    json.encode({
      name: "demo",
      ver: "1.0.0",
      rel: "1",
      deps: [],
      mkdeps_host: [],
      mkdeps_target: [],
      filetree: [{path: "usr/bin/demo", kind: "file"}],
      nostrip: false,
      dir: "/var/tmp/pm-build/demo-1.0.0-1/pkg",
      extract_install: true,
    })?,
  )?
  archive.tar_create(payload, contents, [p"."], compression: "gz")?
  fs.write(proof, "published proof\n")?
  let node: types.PlanNode = {
    name: "demo",
    ver: "1.0.0",
    rel: "1",
    package_id: "demo-1.0.0-1",
    recipe_dir: p"repo/demo",
    recipe_sha256: digest("published recipe"),
    proof_sha256: digest("published proof input"),
    artifact_key: digest("published artifact"),
    proof_key: digest("published proof key"),
    action: types.plan_action_build("published root metadata"),
    level: 0,
    dependencies: [],
    remote: null,
  }
  let receipt = store.commit(store_root, node, {payload, metadata, proof, executor_sha256: digest("published executor")})?
  let plan = root.preflight([receipt])?

  if plan.entries.len() != 4 or plan.entries[0].path != "usr/bin/demo" {
    return error.fail("published legacy metadata did not materialize its package database entries")
  }

  # Distinct payloads may both declare the same structural directories. The
  # receipt keeps the lexically first package as their single deterministic
  # owner, while the path-specific metadata must still agree exactly.
  let shared_alpha_stage = fp"${workspace}/shared-alpha"
  let shared_alpha_contents = fp"${shared_alpha_stage}/contents"
  let shared_alpha_payload = fp"${shared_alpha_stage}/payload.tar.gz"
  let shared_alpha_metadata = fp"${shared_alpha_stage}/metadata.json"
  let shared_alpha_proof = fp"${shared_alpha_stage}/proof.json"
  fs.mkdir(fp"${shared_alpha_contents}/usr/share", parents: true)?
  fs.chmod(fp"${shared_alpha_contents}/usr", 0o755)?
  fs.chmod(fp"${shared_alpha_contents}/usr/share", 0o755)?
  fs.write(fp"${shared_alpha_contents}/usr/share/alpha", "alpha\n")?
  archive.tar_create(shared_alpha_payload, shared_alpha_contents, [p"."], compression: "gz")?
  fs.write(
    shared_alpha_metadata,
    json.encode({
      name: "shared-alpha",
      ver: "1.0.0",
      rel: "1",
      package_kind: "payload",
      files: [
        {path: "usr", kind: "tree", mode: 0o755, sha256: "", target: ""},
        {path: "usr/share", kind: "tree", mode: 0o755, sha256: "", target: ""},
        {path: "usr/share/alpha", kind: "file", mode: 0o644, sha256: digest("alpha\n"), target: ""},
      ],
    })? + "\n",
  )?
  fs.write(shared_alpha_proof, "shared alpha proof\n")?
  let shared_alpha_node: types.PlanNode = {
    name: "shared-alpha",
    ver: "1.0.0",
    rel: "1",
    package_id: "shared-alpha-1.0.0-1",
    recipe_dir: p"repo/shared-alpha",
    recipe_sha256: digest("shared alpha recipe"),
    proof_sha256: digest("shared alpha proof input"),
    artifact_key: digest("shared alpha artifact"),
    proof_key: digest("shared alpha proof key"),
    action: types.plan_action_build("published shared directory metadata"),
    level: 0,
    dependencies: [],
    remote: null,
  }
  let shared_alpha = store.commit(
    store_root,
    shared_alpha_node,
    {payload: shared_alpha_payload, metadata: shared_alpha_metadata, proof: shared_alpha_proof, executor_sha256: digest("published executor")},
  )?

  let shared_beta_stage = fp"${workspace}/shared-beta"
  let shared_beta_contents = fp"${shared_beta_stage}/contents"
  let shared_beta_payload = fp"${shared_beta_stage}/payload.tar.gz"
  let shared_beta_metadata = fp"${shared_beta_stage}/metadata.json"
  let shared_beta_proof = fp"${shared_beta_stage}/proof.json"
  fs.mkdir(fp"${shared_beta_contents}/usr/share", parents: true)?
  fs.chmod(fp"${shared_beta_contents}/usr", 0o755)?
  fs.chmod(fp"${shared_beta_contents}/usr/share", 0o755)?
  fs.write(fp"${shared_beta_contents}/usr/share/beta", "beta\n")?
  archive.tar_create(shared_beta_payload, shared_beta_contents, [p"."], compression: "gz")?
  fs.write(
    shared_beta_metadata,
    json.encode({
      name: "shared-beta",
      ver: "1.0.0",
      rel: "1",
      package_kind: "payload",
      files: [
        {path: "usr", kind: "tree", mode: 0o755, sha256: "", target: ""},
        {path: "usr/share", kind: "tree", mode: 0o755, sha256: "", target: ""},
        {path: "usr/share/beta", kind: "file", mode: 0o644, sha256: digest("beta\n"), target: ""},
      ],
    })? + "\n",
  )?
  fs.write(shared_beta_proof, "shared beta proof\n")?
  let shared_beta_node: types.PlanNode = {
    name: "shared-beta",
    ver: "1.0.0",
    rel: "1",
    package_id: "shared-beta-1.0.0-1",
    recipe_dir: p"repo/shared-beta",
    recipe_sha256: digest("shared beta recipe"),
    proof_sha256: digest("shared beta proof input"),
    artifact_key: digest("shared beta artifact"),
    proof_key: digest("shared beta proof key"),
    action: types.plan_action_build("published shared directory metadata"),
    level: 0,
    dependencies: [],
    remote: null,
  }
  let shared_beta = store.commit(
    store_root,
    shared_beta_node,
    {payload: shared_beta_payload, metadata: shared_beta_metadata, proof: shared_beta_proof, executor_sha256: digest("published executor")},
  )?
  let shared_directories = root.preflight([shared_beta, shared_alpha])?

  if shared_directories.entries.len() != 4
    or [entry.package_name for entry in shared_directories.entries if entry.kind == types.file_kind_tree()] != ["shared-alpha", "shared-alpha"] {
    return error.fail("published root preflight did not coalesce identical shared directories")
  }
  let shared_output = fp"${workspace}/shared-root"
  let shared_receipt = root.compose_artifacts(shared_output, shared_directories, [shared_beta, shared_alpha])?

  if fp"${shared_output}/usr/share/alpha".read_text()? != "alpha\n"
    or fp"${shared_output}/usr/share/beta".read_text()? != "beta\n" {
    return error.fail("published root composition did not merge preflighted payload files")
  }

  root.verify(shared_output, shared_receipt)?

  print "root-published-metadata-ok"
}

main()?
