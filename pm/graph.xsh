##! Deterministic typed dependency graph resolution.
use policy
use types

pure graph_sorted_unique_names(names: List[Str]) -> List[Str] {
  var unique: List[Str] = []
  var seen: Map[Bool] = {}

  for name in names |> sort {
    if ! seen.get(name, false) {
      unique = unique.push(name)
      seen[name] = true
    }
  }

  unique
}

pure kind_is_selected(kind: types.DependencyKind, kinds: List[types.DependencyKind]) -> Bool {
  kind in kinds
}

pure edge_key(from: Str, to: Str) -> Str {
  f"${from}->${to}"
}

pure package_edges(pkg: types.Package, value: types.BuildPolicy) -> List[types.DependencyEdge] {
  var result: List[types.DependencyEdge] = []

  for dependency in pkg.deps {
    let kind = if policy.is_bootstrap_dependency(value, pkg.name, dependency) { types.dependency_bootstrap() } else { types.dependency_runtime() }
    result = result.push({from: pkg.name, to: dependency, kind})
  }

  for dependency in pkg.mkdeps_host {
    let kind = if policy.is_bootstrap_dependency(value, pkg.name, dependency) { types.dependency_bootstrap() } else { types.dependency_build_host() }
    result = result.push({from: pkg.name, to: dependency, kind})
  }

  for dependency in pkg.mkdeps_target {
    let kind = if policy.is_bootstrap_dependency(value, pkg.name, dependency) { types.dependency_bootstrap() } else { types.dependency_build_target() }
    result = result.push({from: pkg.name, to: dependency, kind})
  }

  result
}

pure selected_edges(edges: List[types.DependencyEdge], kinds: List[types.DependencyKind]) -> List[types.DependencyEdge] {
  [edge for edge in edges if kind_is_selected(edge.kind, kinds)]
}

pure direct_dependencies(name: Str, edges: List[types.DependencyEdge]) -> List[Str] {
  graph_sorted_unique_names([edge.to for edge in edges if edge.from == name])
}

pure index_in_path(trail: List[Str], name: Str) -> Int {
  var index = 0

  while index < trail.len() {
    if trail[index] == name {
      return index
    }

    index += 1
  }

  -1
}

pure cycle_from(name: Str, selected: Map[Bool], edges: List[types.DependencyEdge], trail: List[Str]) -> List[Str] {
  for dependency in direct_dependencies(name, edges) {
    continue unless selected.get(dependency, false)
    let cycle_index = index_in_path(trail, dependency)

    if cycle_index >= 0 {
      var cycle: List[Str] = []
      var index = cycle_index

      while index < trail.len() {
        cycle = cycle.push(trail[index])
        index += 1
      }

      return cycle.push(dependency)
    }

    let nested = cycle_from(dependency, selected, edges, trail.push(dependency))

    if nested.len() > 0 {
      return nested
    }
  }

  []
}

pure find_cycle(selected_names: List[Str], edges: List[types.DependencyEdge]) -> List[Str] {
  let selected: Map[Bool] = {name: true for name in selected_names}

  for name in selected_names {
    let cycle = cycle_from(name, selected, edges, [name])

    if cycle.len() > 0 {
      return cycle
    }
  }

  []
}

proc closure_from_edges(
  catalog: types.PackageCatalog,
  roots: List[Str],
  kinds: List[types.DependencyKind],
  edges: List[types.DependencyEdge],
) [error] -> Result[List[Str]] {
  let local_names = {pkg.name: true for pkg in catalog.packages}
  let remote_names = {name: true for name in catalog.remote_names}
  var pending = graph_sorted_unique_names(roots)
  var included: Map[Bool] = {}
  var index = 0

  while index < pending.len() {
    let name = pending[index]

    if ! local_names.get(name, false) and ! remote_names.get(name, false) {
      return Err(types.PmError.MissingDependency(f"graph root ${name} is unavailable"))
    }

    if ! included.get(name, false) {
      included[name] = true

      for dependency in direct_dependencies(name, selected_edges(edges, kinds)) {
        if ! included.get(dependency, false) {
          pending = pending.push(dependency)
        }
      }
    }

    index += 1
  }

  graph_sorted_unique_names([name for name in pending if included.get(name, false)])
}

## Classifies every declared and policy-seeded dependency edge in a catalog.
export proc edges(
  catalog: types.PackageCatalog,
  value: types.BuildPolicy,
) [error] -> Result[List[types.DependencyEdge]] {
  let local_names = {pkg.name: true for pkg in catalog.packages}
  let remote_names = {name: true for name in catalog.remote_names}
  var result: List[types.DependencyEdge] = []
  var declared_pairs: Map[Bool] = {}

  for pkg in catalog.packages {
    for edge in package_edges(pkg, value) {
      result = result.push(edge)
      declared_pairs[edge_key(edge.from, edge.to)] = true
    }
  }

  for rule in value.bootstrap_seeds {
    continue unless (! rule.native_only or value.native_build) and local_names.get(rule.package, false)

    if ! local_names.get(rule.dependency, false) and ! remote_names.get(rule.dependency, false) {
      return Err(types.PmError.MissingDependency(f"${rule.package} bootstrap requires missing ${rule.dependency}"))
    }

    let key = edge_key(rule.package, rule.dependency)

    if ! declared_pairs.get(key, false) {
      result = result.push({from: rule.package, to: rule.dependency, kind: types.dependency_bootstrap()})
    }
  }

  result
}

## Resolves a deterministic dependency closure for selected edge kinds under the default build policy.
export proc closure(
  catalog: types.PackageCatalog,
  roots: List[Str],
  kinds: List[types.DependencyKind],
) [error] -> Result[List[Str]] {
  closure_from_edges(catalog, roots, kinds, edges(catalog, policy.aarch64_docker())?)?
}

## Produces dependency-first lexical topological levels; bootstrap seed edges are externally provided and do not order local builds.
export proc topological_levels(
  selected: List[Str],
  edges: List[types.DependencyEdge],
) [error] -> Result[List[List[Str]]] {
  let selected_names = graph_sorted_unique_names(selected)
  let selected_map: Map[Bool] = {name: true for name in selected_names}
  let local_edges = [
    edge
    for edge in edges
    if edge.kind != types.dependency_bootstrap() and selected_map.get(edge.from, false) and selected_map.get(edge.to, false)
  ]
  var unresolved: Map[Int] = {}
  var emitted: Map[Bool] = {}
  var levels: List[List[Str]] = []

  for name in selected_names {
    unresolved[name] = 0
  }

  for edge in local_edges {
    unresolved[edge.from] = unresolved.get(edge.from, 0) + 1
  }

  var emitted_count = 0

  while emitted_count < selected_names.len() {
    var ready: List[Str] = []

    for name in selected_names {
      if ! emitted.get(name, false) and unresolved.get(name, 0) == 0 {
        ready = ready.push(name)
      }
    }

    if ready.len() == 0 {
      let cycle = find_cycle(selected_names, local_edges)
      let rendered = if cycle.len() > 0 { cycle.join(" -> ") } else { selected_names.join(", ") }
      return Err(types.PmError.DependencyCycle(f"package dependency cycle: ${rendered}"))
    }

    levels = levels.push(ready)

    for name in ready {
      emitted[name] = true
      emitted_count += 1

      for edge in local_edges {
        if edge.to == name {
          unresolved[edge.from] = unresolved.get(edge.from, 0) - 1
        }
      }
    }
  }

  levels
}

## Resolves runtime dependencies only, excluding host and target build dependencies.
export proc runtime_closure(catalog: types.PackageCatalog, roots: List[Str]) [error] -> Result[List[Str]] {
  closure(catalog, roots, [types.dependency_runtime()])?
}

## Resolves all runtime, host-build, target-build, and bootstrap dependencies required to build selected roots.
export proc build_closure(
  catalog: types.PackageCatalog,
  roots: List[Str],
  value: types.BuildPolicy,
) [error] -> Result[List[Str]] {
  closure_from_edges(
    catalog,
    roots,
    [types.dependency_runtime(), types.dependency_build_host(), types.dependency_build_target(), types.dependency_bootstrap()],
    edges(catalog, value)?,
  )?
}
