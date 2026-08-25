##! Typed package catalog discovery and validation.
use recipe
use types

pure sorted_unique_names(names: List[Str]) -> List[Str] {
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

pure package_dependencies(pkg: types.Package) -> List[Str] {
  pkg.deps.extend(pkg.mkdeps_host).extend(pkg.mkdeps_target)
}

proc make_catalog(
  root: Path,
  packages: List[types.Package],
  remote_names: List[Str],
) [error] -> Result[types.PackageCatalog] {
  let sorted_packages = packages |> sort-by .name
  let available_remote_names = sorted_unique_names(remote_names)
  var local_names: Map[Bool] = {}
  var available_names: Map[Bool] = {}

  for name in available_remote_names {
    available_names[name] = true
  }

  for pkg in sorted_packages {
    if local_names.has(pkg.name) {
      return Err(types.PmError.PackageContract(f"duplicate package ${pkg.name}"))
    }

    local_names[pkg.name] = true
    available_names[pkg.name] = true
  }

  for pkg in sorted_packages {
    for dependency in package_dependencies(pkg) {
      if ! available_names.has(dependency) {
        return Err(types.PmError.MissingDependency(f"${pkg.name} depends on missing ${dependency}"))
      }
    }
  }

  {root, packages: sorted_packages, remote_names: available_remote_names}
}

## Builds a validated in-memory catalog from typed packages and selected remote package names.
export proc from_packages(
  root: Path,
  packages: List[types.Package],
  remote_names: List[Str] = [],
) [error] -> Result[types.PackageCatalog] {
  make_catalog(root, packages, remote_names)?
}

## Revalidates a catalog after supplying names available from the selected remote snapshot.
export proc with_remote_names(
  value: types.PackageCatalog,
  remote_names: List[Str],
) [error] -> Result[types.PackageCatalog] {
  make_catalog(value.root, value.packages, value.remote_names.extend(remote_names))?
}

## Returns the catalog package names in canonical lexical order.
export pure package_names(value: types.PackageCatalog) -> List[Str] {
  [pkg.name for pkg in value.packages]
}

## Returns a typed package lookup map for graph and execution adapters.
export pure package_map(value: types.PackageCatalog) -> Map[types.Package] {
  {pkg.name: pkg for pkg in value.packages}
}

## Discovers and validates every `repo/*/PKGBUILD.xsh` package below a repository root.
export proc load(root: Path) [fs, env, error] -> Result[types.PackageCatalog] {
  let absolute_root = path.absolute(root)?
  let recipe_root = fp"${absolute_root}/repo"

  if ! fs.exists(recipe_root)? {
    return Err(types.PmError.PackageContract(f"${absolute_root.display()} does not contain repo"))
  }

  var packages: List[types.Package] = []

  for entry in fs.children(recipe_root)? |> sort-by .name {
    continue unless entry.kind == "dir"
    continue unless fs.exists(fp"${entry.path}/PKGBUILD.xsh")?

    let pkg = recipe.load_package(entry.path)?
    let durable_dir = pkg.dir.relative_to(absolute_root)
    packages = packages.push({...pkg, dir: durable_dir})
  }

  make_catalog(absolute_root, packages, [])?
}
