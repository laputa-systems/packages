##! Isolated typed graph contracts without recipe loading or package execution.
use pm.graph
use pm.types

test graph_levels_deduplicate_selection_and_ignore_external_edges [error] {
  let edges = [
    {from: "app", to: "library", kind: types.dependency_runtime()},
    {from: "app", to: "seed", kind: types.dependency_bootstrap()},
    {from: "unselected", to: "app", kind: types.dependency_runtime()},
    {from: "app", to: "external", kind: types.dependency_build_host()},
  ]
  graph.topological_levels(["tool", "app", "library", "app"], edges)? == [["library", "tool"], ["app"]]
  graph.topological_levels([], edges)? == []
}

test graph_cycle_retains_package_error_and_deterministic_path [error] {
  let edges = [
    {from: "beta", to: "alpha", kind: types.dependency_runtime()},
    {from: "alpha", to: "beta", kind: types.dependency_build_target()},
  ]
  match graph.topological_levels(["beta", "alpha"], edges) {
    Ok(_) => test.fail("dependency cycle unexpectedly received levels")?
    Err(problem) => problem == types.PmError.DependencyCycle("package dependency cycle: alpha -> beta -> alpha")
  }
}

test plan_action_enum_preserves_external_identity_and_reason [error] {
  let built = types.parse_plan_action("build", "recipe changed")?
  let reused = types.parse_plan_action("reuse-remote", "artifact verified")?
  types.plan_action_text(built) == "build"
  types.plan_action_reason(built) == "recipe changed"
  types.plan_action_is_build(built)
  types.plan_action_text(reused) == "reuse-remote"
  types.plan_action_reason(reused) == "artifact verified"
  ! types.plan_action_is_build(reused)
  types.parse_plan_action("unknown", "") is Err(_)
}
