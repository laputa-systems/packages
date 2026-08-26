##! Deterministic typed package build-plan resolution and canonical fingerprints.
use catalog
use fingerprint as pm_fingerprint
use graph
use types
use util

## The durable on-disk and in-memory build-plan format.
export let format: Str = "laputa-build-plan-1"

pure plan_canonical_field(value: Str) -> Str {
  value.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")
}

proc plan_digest_lines(lines: List[Str]) [error] -> Result[Str] {
  bytes.from_text((lines |> sort).join("\n") + "\n").sha256().hex()
}

pure dependency_key(value: types.PlanDependency) -> Str {
  f"${types.dependency_kind_text(value.kind)}\t${value.name}"
}

pure node_is_before(left: types.PlanNode, right: types.PlanNode) -> Bool {
  left.level < right.level or left.level == right.level and left.name < right.name
}

pure plan_sorted_unique_names(names: List[Str]) -> List[Str] {
  var result: List[Str] = []
  var seen: Map[Bool] = {}

  for name in names |> sort {
    if ! seen.get(name, false) {
      result = result.push(name)
      seen[name] = true
    }
  }

  result
}

proc exact_executor_fingerprint(value: types.ExecutorIdentity) [error] -> Result[Str] {
  plan_digest_lines([
    "format\tlaputa-executor-identity-1",
    f"executor-format\t${plan_canonical_field(value.format)}",
    f"pm\t${plan_canonical_field(value.pm_sha256)}",
    f"xsh\t${plan_canonical_field(value.xsh_sha256)}",
    f"core\t${plan_canonical_field(value.core_sha256)}",
  ])
}

## Computes the durable executor identity digest used by remote artifact metadata.
export proc executor_fingerprint(value: types.ExecutorIdentity) [error] -> Result[Str] {
  exact_executor_fingerprint(value)?
}

proc artifact_key_for(
  target: types.Target,
  package_id: Str,
  recipe_sha256: Str,
  executor: types.ExecutorIdentity,
  dependencies: List[types.PlanDependency],
) [error] -> Result[Str] {
  var lines = [
    "format\tlaputa-package-artifact-key-1",
    f"target\t${types.target_text(target)}",
    f"package\t${plan_canonical_field(package_id)}",
    f"recipe\t${plan_canonical_field(recipe_sha256)}",
    f"executor\t${exact_executor_fingerprint(executor)?}",
  ]

  for dependency in dependencies |> sort-by { |dependency| dependency_key(dependency) } {
    lines = lines.push(
      f"dependency\t${types.dependency_kind_text(dependency.kind)}\t${plan_canonical_field(dependency.name)}\t${plan_canonical_field(dependency.artifact_key)}",
    )
  }

  plan_digest_lines(lines)?
}

proc legacy_remote_artifact_key(package_id: Str, remote: types.RemoteRetrieval) [error] -> Result[Str] {
  plan_digest_lines([
    "format\tlaputa-legacy-remote-artifact-1",
    f"arch\t${plan_canonical_field(remote.arch)}",
    f"package\t${plan_canonical_field(package_id)}",
    f"tarball\t${plan_canonical_field(remote.tarball)}",
    f"tarball-sha256\t${plan_canonical_field(remote.tarball_sha256)}",
    f"metadata\t${plan_canonical_field(remote.metadata)}",
    f"metadata-sha256\t${plan_canonical_field(remote.metadata_sha256)}",
  ])?
}

proc proof_key_for(package_id: Str, artifact_key: Str, proof_sha256: Str) [error] -> Result[Str] {
  plan_digest_lines([
    "format\tlaputa-package-proof-key-1",
    f"package\t${plan_canonical_field(package_id)}",
    f"artifact\t${plan_canonical_field(artifact_key)}",
    f"proof\t${plan_canonical_field(proof_sha256)}",
  ])?
}

proc absolute_recipe_package(value: types.PackageCatalog, pkg: types.Package) [fs, error] -> Result[types.Package] {
  let dir = if pkg.dir.display().starts_with("/") { pkg.dir } else { fp"${value.root}/${pkg.dir}" }
  {...pkg, dir}
}

proc durable_recipe_dir(value: types.PackageCatalog, pkg: types.Package) [error] -> Result[Path] {
  let durable = if pkg.dir.display().starts_with("/") { pkg.dir.relative_to(value.root) } else { pkg.dir }
  util.ensure_relative_path(durable, "plan recipe directory")?
}

proc repository_fingerprint(value: types.PackageCatalog, target: types.Target) [fs, error] -> Result[Str] {
  var lines = ["format\tlaputa-package-repository-1", f"target\t${types.target_text(target)}"]

  for pkg in value.packages |> sort-by .name {
    let source_pkg = absolute_recipe_package(value, pkg)?
    let input = pm_fingerprint.package_build_input(value.root, source_pkg, target)?
    lines = lines.push(f"package\t${plan_canonical_field(pkg.name)}\t${input}")
  }

  plan_digest_lines(lines)?
}

proc find_remote(
  snapshot: types.RemoteSnapshot,
  name: Str,
) [error] -> Result[types.RemotePlanArtifact?] {
  var selected: types.RemotePlanArtifact? = null

  for candidate in snapshot.packages {
    if candidate.name == name {
      if selected != null {
        return Err(types.PmError.PackageContract(f"remote snapshot has duplicate package ${name}"))
      }

      selected = candidate
    }
  }

  selected
}

pure plan_compare_lex(left: Str, right: Str) -> Int {
  if left == right {
    return 0
  }

  if ([left, right] |> sort)[0] == left {
    return -1
  }

  1
}

pure plan_version_parts(value: Str) -> List[Str] {
  value.replace("-", ".").replace("_", ".").replace("+", ".").split(".")
}

pure plan_compare_version_part(left: Str, right: Str) -> Int {
  let left_num = left.parse_int() ?? -1
  let right_num = right.parse_int() ?? -1
  let left_is_num = f"${left_num}" == left
  let right_is_num = f"${right_num}" == right

  if left_is_num and right_is_num {
    if left_num < right_num {
      return -1
    }

    if left_num > right_num {
      return 1
    }

    return 0
  }

  plan_compare_lex(left, right)
}

pure plan_compare_version_release(left_ver: Str, left_rel: Str, right_ver: Str, right_rel: Str) -> Int {
  let left_parts = plan_version_parts(left_ver)
  let right_parts = plan_version_parts(right_ver)
  let total = if left_parts.len() > right_parts.len() { left_parts.len() } else { right_parts.len() }
  var index = 0

  while index < total {
    let result = plan_compare_version_part(left_parts.get(index, "0"), right_parts.get(index, "0"))

    if result != 0 {
      return result
    }

    index += 1
  }

  plan_compare_version_part(left_rel, right_rel)
}

proc require_supported_target(target: types.Target, label: Str) [error] {
  if types.target_text(target) != "aarch64-linux-musl" {
    return Err(types.PmError.PackageContract(f"${label} must target aarch64-linux-musl"))
  }
}

proc remote_is_exact(
  remote: types.RemotePlanArtifact,
  recipe_sha256: Str,
  proof_sha256: Str,
  artifact_key: Str,
  proof_key: Str,
  executor: types.ExecutorIdentity,
) [error] -> Result[Bool] {
  if remote.artifact_key == "" {
    return false
  }

  remote.artifact_key == artifact_key and
    remote.recipe_sha256 == recipe_sha256 and
    remote.executor_sha256 == exact_executor_fingerprint(executor)? and
    remote.proof_key == proof_key and
    remote.proof_sha256 == proof_sha256
}

proc dependency_nodes(
  name: Str,
  edges: List[types.DependencyEdge],
  selected: Map[Bool],
  keys: Map[Str],
) [error] -> Result[List[types.PlanDependency]] {
  var dependencies: List[types.PlanDependency] = []

  for edge in edges {
    continue unless edge.from == name and edge.kind != types.dependency_bootstrap() and selected.get(edge.to, false)

    if ! keys.has(edge.to) {
      return Err(types.PmError.PackageContract(f"${name} dependency ${edge.to} was not resolved before its build-plan node"))
    }

    dependencies = dependencies.push({name: edge.to, kind: edge.kind, artifact_key: keys.get(edge.to)?})
  }

  dependencies |> sort-by { |dependency| dependency_key(dependency) }
}

proc built_dependency_names(
  name: Str,
  edges: List[types.DependencyEdge],
  selected: Map[Bool],
  actions: Map[types.PlanAction],
) [error] -> Result[List[Str]] {
  var changed: List[Str] = []

  for edge in edges {
    continue unless edge.from == name and edge.kind != types.dependency_bootstrap() and selected.get(edge.to, false)

    if types.plan_action_is_build(actions.get(edge.to)?) {
      changed = changed.push(edge.to)
    }
  }

  changed |> sort
}

## Resolves a canonical build plan from a typed local catalog and immutable remote snapshot.
export proc resolve(
  value: types.PackageCatalog,
  snapshot: types.RemoteSnapshot,
  policy: types.BuildPolicy,
  roots: List[Str],
  all: Bool,
  identity: types.ExecutorIdentity,
) [fs, error] -> Result[types.BuildPlan] {
  require_supported_target(policy.target, "build policy")?
  require_supported_target(policy.build_target, "build policy")?
  require_supported_target(snapshot.target, "remote snapshot")?

  if snapshot.target != policy.target {
    return Err(types.PmError.PackageContract("remote snapshot target does not match build policy"))
  }

  if identity.format != "laputa-pm-executor-1" {
    return Err(types.PmError.PackageContract(f"unsupported executor identity ${identity.format}"))
  }

  let canonical_roots = plan_sorted_unique_names(roots)
  let selected_roots = if all { catalog.package_names(value) } else { canonical_roots }

  if selected_roots.len() == 0 {
    return Err(types.PmError.Usage("build plan requires --all or one or more roots"))
  }

  let selected_names = graph.build_closure(value, selected_roots, policy)?
  let selected: Map[Bool] = {name: true for name in selected_names}
  let packages = catalog.package_map(value)

  for name in selected_names {
    if ! packages.has(name) {
      return Err(types.PmError.MissingDependency(f"build plan needs a local recipe for ${name}"))
    }
  }

  let edges = graph.edges(value, policy)?
  let levels = graph.topological_levels(selected_names, edges)?
  let repository_digest = repository_fingerprint(value, policy.target)?
  var nodes: List[types.PlanNode] = []
  var keys: Map[Str] = {}
  var actions: Map[types.PlanAction] = {}
  var level = 0

  for names in levels {
    for name in names {
      let pkg: types.Package = packages.get(name)?
      let source_pkg = absolute_recipe_package(value, pkg)?
      let recipe_dir = durable_recipe_dir(value, pkg)?
      let package_id = util.package_id(pkg.name, pkg.ver, pkg.rel)
      let dependencies = dependency_nodes(name, edges, selected, keys)?
      let recipe_sha256 = pm_fingerprint.package_build_input(value.root, source_pkg, policy.target)?
      let proof_sha256 = pm_fingerprint.package_proof_input(value.root, source_pkg)?
      let local_artifact_key = artifact_key_for(policy.target, package_id, recipe_sha256, identity, dependencies)?
      let local_proof_key = proof_key_for(package_id, local_artifact_key, proof_sha256)?
      let changed_dependencies = built_dependency_names(name, edges, selected, actions)?
      var artifact_key = local_artifact_key
      var action: types.PlanAction = types.plan_action_build("new package")
      var remote: types.RemoteRetrieval? = null

      let candidate = find_remote(snapshot, name)?

      if candidate != null {
          let tuple_order = plan_compare_version_release(pkg.ver, pkg.rel, candidate.ver, candidate.rel)

          if tuple_order < 0 {
            return Err(
              types.PmError.PackageContract(
                f"${name} declares ${util.version_id(pkg.ver, pkg.rel)} behind remote ${util.version_id(candidate.ver, candidate.rel)}; bump PKGBUILD.xsh rel explicitly",
              ),
            )
          }

          if tuple_order > 0 {
            let reason = if pkg.ver != candidate.ver {
              f"local version differs from remote ${util.version_id(candidate.ver, candidate.rel)}"
            } else {
              f"local release is above remote ${util.version_id(candidate.ver, candidate.rel)}"
            }
            action = types.plan_action_build(reason)
          } else if changed_dependencies.len() > 0 {
            return Err(
              types.PmError.PackageContract(
                f"${name} dependencies changed (${changed_dependencies.join(", ")}); bump PKGBUILD.xsh rel above ${util.version_id(candidate.ver, candidate.rel)}",
              ),
            )
          } else if remote_is_exact(candidate, recipe_sha256, proof_sha256, local_artifact_key, local_proof_key, identity)? {
            action = types.plan_action_reuse_remote("exact remote artifact")
            remote = candidate.retrieval
          } else if candidate.artifact_key != "" {
            action = types.plan_action_build("remote artifact identity differs")
          } else {
            artifact_key = legacy_remote_artifact_key(package_id, candidate.retrieval)?
            action = types.plan_action_reuse_remote("legacy remote artifact")
            remote = candidate.retrieval
          }
      }

      let proof_key = proof_key_for(package_id, artifact_key, proof_sha256)?
      let node = {
        name: pkg.name,
        ver: pkg.ver,
        rel: pkg.rel,
        package_id,
        recipe_dir,
        recipe_sha256,
        proof_sha256,
        artifact_key,
        proof_key,
        action,
        level,
        dependencies,
        remote,
      }
      keys[name] = artifact_key
      actions[name] = action
      nodes = nodes.push(node)
    }

    level += 1
  }

  let bare = {
    format,
    target: policy.target,
    roots: selected_roots,
    repository_digest,
    remote_index_sha256: snapshot.index_sha256,
    executor: identity,
    nodes,
    plan_sha256: "",
  }
  let plan_sha256 = fingerprint(bare)?
  {...bare, plan_sha256}
}

proc validate_executor(value: types.ExecutorIdentity) [error] {
  if value.format != "laputa-pm-executor-1" {
    return Err(types.PmError.PackageContract(f"unsupported executor identity ${value.format}"))
  }

  if value.pm_sha256 == "" or value.xsh_sha256 == "" or value.core_sha256 == "" {
    return Err(types.PmError.PackageContract("executor identity is incomplete"))
  }
}

proc validate_retrieval(value: types.RemoteRetrieval) [error] {
  if value.arch != "aarch64" {
    return Err(types.PmError.PackageContract(f"unsupported remote artifact architecture ${value.arch}"))
  }

  let _ = util.ensure_relative_path(fp"${value.tarball}", "plan remote tarball")?
  let _ = util.ensure_relative_path(fp"${value.metadata}", "plan remote metadata")?

  if value.tarball_sha256 == "" or value.metadata_sha256 == "" {
    return Err(types.PmError.PackageContract("remote retrieval hashes are required"))
  }
}

proc validate_node(
  value: types.BuildPlan,
  node: types.PlanNode,
  seen: Map[Bool],
  levels: Map[Int],
  artifact_keys: Map[Str],
) [error] {
  if seen.get(node.name, false) {
    return Err(types.PmError.PackageContract(f"build plan has duplicate node ${node.name}"))
  }

  if node.package_id != util.package_id(node.name, node.ver, node.rel) {
    return Err(types.PmError.PackageContract(f"build plan node ${node.name} has an invalid package id"))
  }

  let _ = util.ensure_relative_path(node.recipe_dir, "plan recipe directory")?
  var dependency_seen: Map[Bool] = {}
  var prior_dependency: types.PlanDependency? = null

  for dependency in node.dependencies {
    let key = dependency_key(dependency)

    if dependency_seen.get(key, false) {
      return Err(
        types.PmError.PackageContract(
          f"build plan node ${node.name} repeats ${types.dependency_kind_text(dependency.kind)} dependency ${dependency.name}",
        ),
      )
    }

    if prior_dependency != null {
      if dependency_key(dependency) < dependency_key(prior_dependency) {
        return Err(types.PmError.PackageContract(f"build plan node ${node.name} dependencies are not ordered"))
      }
    }

    if ! levels.has(dependency.name) {
      return Err(types.PmError.PackageContract(f"build plan node ${node.name} has unresolved dependency ${dependency.name}"))
    }

    if levels.get(dependency.name)? >= node.level {
      return Err(types.PmError.PackageContract(f"build plan node ${node.name} is not dependency-first"))
    }

    if artifact_keys.get(dependency.name)? != dependency.artifact_key {
      return Err(
        types.PmError.PackageContract(
          f"build plan node ${node.name} dependency ${dependency.name} artifact key does not match its referenced node",
        ),
      )
    }

    dependency_seen[key] = true
    prior_dependency = dependency
  }

  let expected_local = artifact_key_for(value.target, node.package_id, node.recipe_sha256, value.executor, node.dependencies)?

  if types.plan_action_is_build(node.action) {
    if node.remote != null {
      return Err(types.PmError.PackageContract(f"build plan node ${node.name} builds locally but has remote retrieval data"))
    }

    if node.artifact_key != expected_local {
      return Err(types.PmError.PackageContract(f"build plan node ${node.name} artifact key does not match local inputs"))
    }
  } else {
    let retrieval = node.remote

    if retrieval == null {
      return Err(types.PmError.PackageContract(f"build plan node ${node.name} reuses remote without retrieval data"))
    } else {
      validate_retrieval(retrieval)?
      let expected_legacy = legacy_remote_artifact_key(node.package_id, retrieval)?

      if node.artifact_key != expected_local and node.artifact_key != expected_legacy {
        return Err(types.PmError.PackageContract(f"build plan node ${node.name} artifact key does not match remote inputs"))
      }
    }
  }

  if node.proof_key != proof_key_for(node.package_id, node.artifact_key, node.proof_sha256)? {
    return Err(types.PmError.PackageContract(f"build plan node ${node.name} proof key does not match its inputs"))
  }
}

## Reports whether one validated remote node uses the retrieval-derived legacy artifact identity.
## Legacy metadata predates executor fingerprints, so its receipt is bound to verified metadata bytes instead.
export proc node_uses_legacy_remote_identity(value: types.BuildPlan, node: types.PlanNode) [error] -> Result[Bool] {
  if types.plan_action_is_build(node.action) {
    return false
  }

  let retrieval = node.remote

  if retrieval == null {
    return false
  } else {
    let expected_local = artifact_key_for(value.target, node.package_id, node.recipe_sha256, value.executor, node.dependencies)?

    if node.artifact_key == expected_local {
      return false
    }

    let expected_legacy = legacy_remote_artifact_key(node.package_id, retrieval)?
    return node.artifact_key == expected_legacy
  }
}

proc validate_structure(value: types.BuildPlan) [error] {
  if value.format != format {
    return Err(types.PmError.PackageContract(f"unsupported build plan format ${value.format}"))
  }

  require_supported_target(value.target, "build plan")?
  validate_executor(value.executor)?

  let canonical_roots = plan_sorted_unique_names(value.roots)

  if value.roots.len() == 0 or value.roots != canonical_roots {
    return Err(types.PmError.PackageContract("build plan roots must be non-empty, sorted, and unique"))
  }

  var names: Map[Bool] = {}
  var levels: Map[Int] = {}
  var artifact_keys: Map[Str] = {}

  for node in value.nodes {
    if names.get(node.name, false) {
      return Err(types.PmError.PackageContract(f"build plan has duplicate node ${node.name}"))
    }

    names[node.name] = true
    levels[node.name] = node.level
    artifact_keys[node.name] = node.artifact_key
  }

  for root in value.roots {
    if ! names.has(root) {
      return Err(types.PmError.PackageContract(f"build plan root ${root} is not a node"))
    }
  }

  var previous: types.PlanNode? = null
  var seen: Map[Bool] = {}

  for node in value.nodes {
    if previous != null {
      if node_is_before(node, previous) {
        return Err(types.PmError.PackageContract("build plan nodes are not ordered by level and name"))
      }
    }

    validate_node(value, node, seen, levels, artifact_keys)?
    seen[node.name] = true
    previous = node
  }
}

proc fingerprint_unchecked(value: types.BuildPlan) [error] -> Result[Str] {
  var lines = [
    "format\tlaputa-build-plan-fingerprint-1",
    f"plan-format\t${plan_canonical_field(value.format)}",
    f"target\t${types.target_text(value.target)}",
    f"repository\t${plan_canonical_field(value.repository_digest)}",
    f"remote-index\t${plan_canonical_field(value.remote_index_sha256)}",
    f"executor-format\t${plan_canonical_field(value.executor.format)}",
    f"executor-pm\t${plan_canonical_field(value.executor.pm_sha256)}",
    f"executor-xsh\t${plan_canonical_field(value.executor.xsh_sha256)}",
    f"executor-core\t${plan_canonical_field(value.executor.core_sha256)}",
  ]

  for root in value.roots {
    lines = lines.push(f"root\t${plan_canonical_field(root)}")
  }

  for node in value.nodes {
    lines = lines.push(
      f"node\t${node.level}\t${plan_canonical_field(node.name)}\t${plan_canonical_field(node.ver)}\t${plan_canonical_field(node.rel)}\t${plan_canonical_field(node.package_id)}\t${plan_canonical_field(node.recipe_dir.display())}\t${plan_canonical_field(node.recipe_sha256)}\t${plan_canonical_field(node.proof_sha256)}\t${plan_canonical_field(node.artifact_key)}\t${plan_canonical_field(node.proof_key)}\t${types.plan_action_text(node.action)}\t${plan_canonical_field(types.plan_action_reason(node.action))}",
    )

    for dependency in node.dependencies {
      lines = lines.push(
        f"dependency\t${plan_canonical_field(node.name)}\t${types.dependency_kind_text(dependency.kind)}\t${plan_canonical_field(dependency.name)}\t${plan_canonical_field(dependency.artifact_key)}",
      )
    }

    let retrieval = node.remote

    if retrieval != null {
      lines = lines.push(
        f"remote\t${plan_canonical_field(node.name)}\t${plan_canonical_field(retrieval.arch)}\t${plan_canonical_field(retrieval.tarball)}\t${plan_canonical_field(retrieval.tarball_sha256)}\t${plan_canonical_field(retrieval.metadata)}\t${plan_canonical_field(retrieval.metadata_sha256)}",
      )
    }
  }

  plan_digest_lines(lines)?
}

## Computes the plan's canonical line-oriented fingerprint without its own digest field.
export proc fingerprint(value: types.BuildPlan) [error] -> Result[Str] {
  validate_structure(value)?
  fingerprint_unchecked(value)?
}

## Verifies every durable BuildPlan invariant, including the stored plan digest.
export proc validate(value: types.BuildPlan) [error] {
  validate_structure(value)?
  let expected = fingerprint_unchecked(value)?

  if value.plan_sha256 != expected {
    return Err(types.PmError.PackageContract("build plan digest does not match its canonical inputs"))
  }
}

pure color(text: Str, code: Str, colors: Bool) -> Str {
  if colors {
    return f"\u{1b}[${code}m${text}\u{1b}[0m"
  }

  text
}

## Renders a concise deterministic human view of a verified plan.
export proc render(value: types.BuildPlan, colors: Bool) [error] -> Result[Str] {
  validate(value)?
  var lines = [
    f"plan ${value.plan_sha256}",
    f"target ${types.target_text(value.target)}",
    f"roots ${value.roots.join(", ")}",
  ]

  for node in value.nodes {
    let action = types.plan_action_text(node.action)
    let line = f"level ${node.level} ${node.name} ${action} ${node.artifact_key} ${types.plan_action_reason(node.action)}"
    lines = lines.push(color(line, if action == "build" { "1;33" } else { "1;32" }, colors))
  }

  lines.join("\n") + "\n"
}
