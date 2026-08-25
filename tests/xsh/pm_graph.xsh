##! Behavior coverage for typed package catalog and dependency graph resolution.
use pm.catalog
use pm.graph
use pm.policy
use pm.types

pure fixture(name: Str) -> Path {
  fp"tests/xsh/fixtures/${name}"
}

pure has_edge(edges: List[types.DependencyEdge], from: Str, to: Str, kind: types.DependencyKind) -> Bool {
  for edge in edges {
    if edge.from == from and edge.to == to and edge.kind == kind {
      return true
    }
  }

  false
}

pure fixture_package(name: Str, deps: List[Str], mkdeps_host: List[Str], mkdeps_target: List[Str]) -> types.Package {
  {
    dir: fp"repo/${name}",
    name,
    ver: "1",
    rel: "1",
    kind: types.Meta,
    deps,
    mkdeps_host,
    mkdeps_target,
    upstream_sources: [],
    filetree: [],
    nostrip: false,
    source_mirror: false,
  }
}

proc expect_catalog_rejection(root: Path, expected: Str) [fs, env, error] {
  match catalog.load(root) {
    Ok(_) => test.fail(f"${expected}: catalog unexpectedly loaded")?
    Err(problem) => test.contains(problem.message, expected)?
  }
}

proc test_catalog_loads_packages_in_name_order_with_relative_dirs() [fs, env, error] {
  let value = catalog.load(fixture("graph-catalog"))?
  test.eq(catalog.package_names(value), ["app", "host-tool", "runtime-lib", "target-sdk"])?
  test.eq(value.packages[0].dir.display(), "repo/app")?
}

proc test_catalog_rejects_missing_dependency() [fs, env, error] {
  expect_catalog_rejection(fixture("graph-missing"), "app depends on missing missing")?
}

proc test_catalog_rejects_duplicate_package_name() [error] {
  let first = fixture_package("duplicate", [], [], [])
  let second = fixture_package("duplicate", [], [], [])

  match catalog.from_packages(p".", [first, second]) {
    Ok(_) => test.fail("duplicate package catalog unexpectedly loaded")?
    Err(problem) => test.contains(problem.message, "duplicate package duplicate")?
  }
}

proc test_catalog_accepts_selected_remote_dependency_snapshot() [error] {
  let app = fixture_package("app", ["remote-lib"], [], [])
  let value = catalog.from_packages(p".", [app], ["remote-lib"])?
  test.eq(value.remote_names, ["remote-lib"])?
}

proc test_graph_classifies_runtime_and_build_edges() [fs, env, error] {
  let value = catalog.load(fixture("graph-catalog"))?
  let edges = graph.edges(value, policy.aarch64_docker())?
  test.ok(has_edge(edges, "app", "runtime-lib", types.Runtime))?
  test.ok(has_edge(edges, "app", "host-tool", types.BuildHost))?
  test.ok(has_edge(edges, "app", "target-sdk", types.BuildTarget))?
}

proc test_graph_classifies_each_explicit_bootstrap_seed() [fs, env, error] {
  let value = catalog.load(p".")?
  let edges = graph.edges(value, policy.aarch64_docker())?
  test.ok(has_edge(edges, "musl", "llvm-toolchain", types.Bootstrap))?
  test.ok(has_edge(edges, "musl", "zlib", types.Bootstrap))?
  test.ok(has_edge(edges, "gnu-stubs", "llvm-toolchain", types.Bootstrap))?
}

proc test_graph_reports_a_useful_cycle_path() [fs, env, error] {
  let value = catalog.load(fixture("graph-cycle"))?
  let edges = graph.edges(value, policy.aarch64_docker())?

  match graph.topological_levels(catalog.package_names(value), edges) {
    Ok(_) => test.fail("cycle unexpectedly received levels")?
    Err(problem) => test.contains(problem.message, "alpha -> beta -> gamma -> alpha")?
  }
}

proc test_graph_topological_levels_are_dependency_first() [fs, env, error] {
  let value = catalog.load(fixture("graph-catalog"))?
  let edges = graph.edges(value, policy.aarch64_docker())?
  let levels = graph.topological_levels(catalog.package_names(value), edges)?
  test.eq(levels, [["host-tool", "runtime-lib", "target-sdk"], ["app"]])?
}

proc test_runtime_closure_excludes_host_and_target_build_dependencies() [fs, env, error] {
  let value = catalog.load(fixture("graph-catalog"))?
  let closure = graph.runtime_closure(value, ["app"])?
  test.eq(closure, ["app", "runtime-lib"])?
}

proc test_build_closure_includes_runtime_host_and_target_edges() [fs, env, error] {
  let value = catalog.load(fixture("graph-catalog"))?
  let closure = graph.build_closure(value, ["app"], policy.aarch64_docker())?
  test.eq(closure, ["app", "host-tool", "runtime-lib", "target-sdk"])?
}

proc test_edge_kind_changes_the_appropriate_closure() [error] {
  let dependency = fixture_package("dependency", [], [], [])
  let runtime_app = fixture_package("app", ["dependency"], [], [])
  let host_app = fixture_package("app", [], ["dependency"], [])
  let runtime_catalog = catalog.from_packages(p".", [runtime_app, dependency])?
  let host_catalog = catalog.from_packages(p".", [host_app, dependency])?
  test.eq(graph.runtime_closure(runtime_catalog, ["app"])?, ["app", "dependency"])?
  test.eq(graph.runtime_closure(host_catalog, ["app"])?, ["app"])?
  test.eq(graph.build_closure(host_catalog, ["app"], policy.aarch64_docker())?, ["app", "dependency"])?
}

proc test_graph_resolution_is_repeatable() [fs, env, error] {
  let first = catalog.load(fixture("graph-catalog"))?
  let second = catalog.load(fixture("graph-catalog"))?
  let value = policy.aarch64_docker()
  let first_edges = graph.edges(first, value)?
  let second_edges = graph.edges(second, value)?
  let first_levels = graph.topological_levels(catalog.package_names(first), first_edges)?
  let second_levels = graph.topological_levels(catalog.package_names(second), second_edges)?
  test.eq(catalog.package_names(first), catalog.package_names(second))?
  test.eq(first_edges, second_edges)?
  test.eq(first_levels, second_levels)?
  test.eq(graph.build_closure(first, ["app"], value)?, graph.build_closure(second, ["app"], value)?)?
}
