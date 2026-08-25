##! JSON data-transfer boundary for durable typed build plans.
use plan
use types
use util

type ExecutorDto = {format: Str, pm_sha256: Str, xsh_sha256: Str, core_sha256: Str}
type DependencyDto = {name: Str, kind: Str, artifact_key: Str}
type RemoteDto = {arch: Str, tarball: Str, tarball_sha256: Str, metadata: Str, metadata_sha256: Str}
type NodeDto = {
  name: Str,
  ver: Str,
  rel: Str,
  package_id: Str,
  recipe_dir: Str,
  recipe_sha256: Str,
  proof_sha256: Str,
  artifact_key: Str,
  proof_key: Str,
  action: Str,
  reason: Str,
  level: Int,
  dependencies: List[DependencyDto],
  remote: RemoteDto?,
}
type BuildPlanDto = {
  format: Str,
  target: Str,
  roots: List[Str],
  repository_digest: Str,
  remote_index_sha256: Str,
  executor: ExecutorDto,
  nodes: List[NodeDto],
  plan_sha256: Str,
}

pure plan_json_executor_dto(value: types.ExecutorIdentity) -> ExecutorDto {
  {
    format: value.format,
    pm_sha256: value.pm_sha256,
    xsh_sha256: value.xsh_sha256,
    core_sha256: value.core_sha256,
  }
}

pure plan_json_dependency_dto(value: types.PlanDependency) -> DependencyDto {
  {
    name: value.name,
    kind: types.dependency_kind_text(value.kind),
    artifact_key: value.artifact_key,
  }
}

pure plan_json_remote_dto(value: types.RemoteRetrieval) -> RemoteDto {
  {
    arch: value.arch,
    tarball: value.tarball,
    tarball_sha256: value.tarball_sha256,
    metadata: value.metadata,
    metadata_sha256: value.metadata_sha256,
  }
}

pure plan_json_node_dto(value: types.PlanNode) -> NodeDto {
  var remote: RemoteDto? = null

  let retrieval = value.remote

  if retrieval != null {
    remote = plan_json_remote_dto(retrieval)
  }

  {
    name: value.name,
    ver: value.ver,
    rel: value.rel,
    package_id: value.package_id,
    recipe_dir: value.recipe_dir.display(),
    recipe_sha256: value.recipe_sha256,
    proof_sha256: value.proof_sha256,
    artifact_key: value.artifact_key,
    proof_key: value.proof_key,
    action: types.plan_action_text(value.action),
    reason: types.plan_action_reason(value.action),
    level: value.level,
    dependencies: [plan_json_dependency_dto(dependency) for dependency in value.dependencies],
    remote,
  }
}

pure plan_json_dto(value: types.BuildPlan) -> BuildPlanDto {
  {
    format: value.format,
    target: types.target_text(value.target),
    roots: value.roots,
    repository_digest: value.repository_digest,
    remote_index_sha256: value.remote_index_sha256,
    executor: plan_json_executor_dto(value.executor),
    nodes: [plan_json_node_dto(node) for node in value.nodes],
    plan_sha256: value.plan_sha256,
  }
}

pure plan_json_write_dto(value: types.BuildPlan) -> Record {
  var nodes: List[Record] = []

  for node in value.nodes {
    var remote: Record? = null
    let retrieval = node.remote

    if retrieval != null {
      remote = {
        arch: retrieval.arch,
        tarball: retrieval.tarball,
        tarball_sha256: retrieval.tarball_sha256,
        metadata: retrieval.metadata,
        metadata_sha256: retrieval.metadata_sha256,
      }
    }

    var dependencies: List[Record] = []

    for dependency in node.dependencies {
      dependencies = dependencies.push({
        name: dependency.name,
        kind: types.dependency_kind_text(dependency.kind),
        artifact_key: dependency.artifact_key,
      })
    }

    nodes = nodes.push({
      name: node.name,
      ver: node.ver,
      rel: node.rel,
      package_id: node.package_id,
      recipe_dir: node.recipe_dir.display(),
      recipe_sha256: node.recipe_sha256,
      proof_sha256: node.proof_sha256,
      artifact_key: node.artifact_key,
      proof_key: node.proof_key,
      action: types.plan_action_text(node.action),
      reason: types.plan_action_reason(node.action),
      level: node.level,
      dependencies,
      remote,
    })
  }

  {
    format: value.format,
    target: types.target_text(value.target),
    roots: value.roots,
    repository_digest: value.repository_digest,
    remote_index_sha256: value.remote_index_sha256,
    executor: {
      format: value.executor.format,
      pm_sha256: value.executor.pm_sha256,
      xsh_sha256: value.executor.xsh_sha256,
      core_sha256: value.executor.core_sha256,
    },
    nodes,
    plan_sha256: value.plan_sha256,
  }
}

proc plan_json_executor(value: ExecutorDto) [error] -> Result[types.ExecutorIdentity] {
  {
    format: value.format,
    pm_sha256: value.pm_sha256,
    xsh_sha256: value.xsh_sha256,
    core_sha256: value.core_sha256,
  }
}

proc plan_json_dependency(value: DependencyDto) [error] -> Result[types.PlanDependency] {
  {
    name: value.name,
    kind: types.parse_dependency_kind(value.kind)?,
    artifact_key: value.artifact_key,
  }
}

proc plan_json_remote(value: RemoteDto) [error] -> Result[types.RemoteRetrieval] {
  {
    arch: value.arch,
    tarball: value.tarball,
    tarball_sha256: value.tarball_sha256,
    metadata: value.metadata,
    metadata_sha256: value.metadata_sha256,
  }
}

proc plan_json_node(value: NodeDto) [error] -> Result[types.PlanNode] {
  var dependencies: List[types.PlanDependency] = []

  for dependency in value.dependencies {
    dependencies = dependencies.push(plan_json_dependency(dependency)?)
  }

  var remote: types.RemoteRetrieval? = null

  let retrieval = value.remote

  if retrieval != null {
    remote = plan_json_remote(retrieval)?
  }

  {
    name: value.name,
    ver: value.ver,
    rel: value.rel,
    package_id: value.package_id,
    recipe_dir: util.ensure_relative_path(fp"${value.recipe_dir}", "plan recipe directory")?,
    recipe_sha256: value.recipe_sha256,
    proof_sha256: value.proof_sha256,
    artifact_key: value.artifact_key,
    proof_key: value.proof_key,
    action: types.parse_plan_action(value.action, value.reason)?,
    level: value.level,
    dependencies,
    remote,
  }
}

proc plan_json_from_dto(value: BuildPlanDto) [error] -> Result[types.BuildPlan] {
  var nodes: List[types.PlanNode] = []

  for node in value.nodes {
    nodes = nodes.push(plan_json_node(node)?)
  }

  {
    format: value.format,
    target: types.parse_target(value.target)?,
    roots: value.roots,
    repository_digest: value.repository_digest,
    remote_index_sha256: value.remote_index_sha256,
    executor: plan_json_executor(value.executor)?,
    nodes,
    plan_sha256: value.plan_sha256,
  }
}

## Atomically writes a validated BuildPlan through its JSON DTO, never through internal tag unions.
export proc write_plan(path_value: Path, value: types.BuildPlan) [fs, error] {
  plan.validate(value)?
  fs.mkdir(path_value.parent)?
  let dto = plan_json_write_dto(value)
  fs.write_atomic(path_value, json.encode(dto)? + "\n")?
}

## Compatibility spelling for the durable BuildPlan write contract.
## The current native-test indexed backend cannot encode a reachable exported write proc;
## callers use write_plan for host-independent behavior coverage until that backend limitation lifts.
export proc write(path_value: Path, value: types.BuildPlan) [fs, error] {
  write_plan(path_value, value)?
}

## Reads a build plan through its JSON DTO and verifies every durable invariant.
export proc read(path_value: Path) [fs, error] -> Result[types.BuildPlan] {
  let dto = json.read(path_value)?.require(BuildPlanDto)?
  let value = plan_json_from_dto(dto)?
  plan.validate(value)?
  value
}

## Re-exports durable BuildPlan verification at the JSON persistence boundary.
export proc verify(value: types.BuildPlan) [error] {
  plan.validate(value)?
}
