##! PM elfdeps operations and shared package-manager policy.
use elf
use local
use util

## Exported PM declaration `ElfDependencyFailure`.
export type ElfDependencyFailure = {pkg: Str, file: Path, soname: Str, provider: Str}

pure path_basename_text(path_value: Path) -> Str {
  let text = path_value.display()
  let parts = text.split("/")
  parts.get(parts.len() - 1, text)
}

pure path_may_provide_library(rel_path: Path) -> Bool {
  let text = rel_path.display()
  return (text.starts_with("lib/") or text.starts_with("usr/lib/")) and ".so" in path_basename_text(rel_path)
}

## Exported PM declaration `elf_info_mentions_musl`.
export pure elf_info_mentions_musl(needed: List[Str], interpreter: Str) -> Bool {
  if "ld-musl-" in interpreter {
    return true
  }

  return "libc.so" in needed
}

## Exported PM declaration `runtime_dependency_closure`.
export pure runtime_dependency_closure(initial: List[Str], package_deps: Map[List[Str]]) -> Map[Bool] {
  var closure: Map[Bool] = {}
  var pending = initial
  var index = 0

  while index < pending.len() {
    let name = pending[index]
    index += 1
    continue when closure.get(name, false)
    closure[name] = true

    if package_deps.has(name) {
      pending = pending.extend(package_deps.get(name, []))
    }
  }

  closure
}

## Exported PM declaration `missing_elf_runtime_dependencies`.
export pure missing_elf_runtime_dependencies(
  pkg_name: Str,
  deps: List[Str],
  needed: List[Str],
  interpreter: Str,
  providers: Map[Str],
) -> List[ElfDependencyFailure] {
  var allowed: Map[Bool] = {}

  for dep in deps {
    allowed[dep] = true
  }

  missing_elf_runtime_dependencies_with_allowed(pkg_name, allowed, needed, interpreter, providers)
}

## Exported PM declaration `missing_elf_runtime_dependencies_with_allowed`.
export pure missing_elf_runtime_dependencies_with_allowed(
  pkg_name: Str,
  allowed: Map[Bool],
  needed: List[Str],
  interpreter: Str,
  providers: Map[Str],
) -> List[ElfDependencyFailure] {
  var failures: List[ElfDependencyFailure] = []

  if elf_info_mentions_musl(needed, interpreter) and pkg_name != "musl" and ! allowed.get("musl", false) {
    failures = failures.push({pkg: pkg_name, file: fp"", soname: "libc.so", provider: "musl"})
  }

  for soname in needed {
    continue unless providers.has(soname)
    let provider = providers.get(soname, "")

    if provider != pkg_name and ! allowed.get(provider, false) {
      failures = failures.push({pkg: pkg_name, file: fp"", soname, provider})
    }
  }

  failures
}

## Exported PM declaration `collect_library_providers`.
export proc collect_library_providers(root: Path) [fs, error] -> Result[Map[Str]] {
  var providers: Map[Str] = {}
  let packages_db = util.packages_db_path(root)

  if ! fs.exists(packages_db)? {
    return providers
  }

  let entries = fs.children(packages_db)
    |> where .kind == "dir"
    |> sort-by .name

  for entry in entries {
    let manifest = local.load_manifest(entry.path)?

    for rel_path in manifest {
      let path_value = fp"${root}/${rel_path}"
      continue unless path_value.exists()?
      continue unless fs.metadata(path_value)?.kind == "file"

      match elf.inspect(path_value) {
        Ok(info) => {
          if info.soname != "" {
            providers[info.soname] = entry.name
          } else if path_may_provide_library(rel_path) {
            providers[path_basename_text(rel_path)] = entry.name
          }
        }
        Err(_) => {
          if path_may_provide_library(rel_path) {
            providers[path_basename_text(rel_path)] = entry.name
          }
        }
      }
    }
  }

  providers
}

## Exported PM declaration `installed_file_elf_dependency_failures`.
export proc installed_file_elf_dependency_failures(
  pkg_name: Str,
  allowed: Map[Bool],
  rel_path: Path,
  path_value: Path,
  providers: Map[Str],
) [fs, error] -> Result[List[ElfDependencyFailure]] {
  if fs.metadata(path_value)?.kind == "symlink" {
    return []
  }

  match elf.inspect(path_value) {
    Ok(info) => {
      var failures = missing_elf_runtime_dependencies_with_allowed(
        pkg_name,
        allowed,
        info.needed,
        info.interpreter,
        providers,
      )

      failures = [{pkg: failure.pkg, file: rel_path, soname: failure.soname, provider: failure.provider} for failure in failures]
      failures
    }
    Err(_) => []
  }
}
