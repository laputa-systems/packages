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
  assert graph.topological_levels(["tool", "app", "library", "app"], edges)? == [["library", "tool"], ["app"]]
  assert graph.topological_levels([], edges)? == []
}

test graph_cycle_retains_package_error_and_deterministic_path [error] {
  let edges = [
    {from: "beta", to: "alpha", kind: types.dependency_runtime()},
    {from: "alpha", to: "beta", kind: types.dependency_build_target()},
  ]
  match graph.topological_levels(["beta", "alpha"], edges) {
    Ok(_) => test.fail("dependency cycle unexpectedly received levels")?
    Err(problem) => assert problem == types.PmError.DependencyCycle("package dependency cycle: alpha -> beta -> alpha")
  }
}

test plan_action_enum_preserves_external_identity_and_reason [error] {
  let built = types.parse_plan_action("build", "recipe changed")?
  let reused = types.parse_plan_action("reuse-remote", "artifact verified")?
  assert types.plan_action_text(built) == "build"
  assert types.plan_action_reason(built) == "recipe changed"
  assert types.plan_action_is_build(built)
  assert types.plan_action_text(reused) == "reuse-remote"
  assert types.plan_action_reason(reused) == "artifact verified"
  assert ! types.plan_action_is_build(reused)
  assert types.parse_plan_action("unknown", "") is Err(_)
}
