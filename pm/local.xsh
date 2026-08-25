##! PM local operations and shared package-manager policy.
use catalog
use elf
use extensions
use graph
use policy
use recipe
use sources
use types
use util

## Exported PM declaration `collect_manifest_text`.
export pure collect_manifest_text(manifest: List[Path]) -> Result[List[Str]] {
  let lines = [rel_path.display() for rel_path in manifest]
  lines
}

## Exported PM declaration `load_manifest`.
export proc load_manifest(db: Path) [fs, error] -> Result[List[Path]] {
  var manifest = []

  if fs.exists(fp"${db}/manifest.json")? {
    let stored: List[Str] = json.read(fp"${db}/manifest.json")?

    for rel_text in stored {
      manifest = manifest.push(fp"${rel_text}")
    }
  }

  manifest
}

## Exported PM declaration `map_etcsums`.
export proc map_etcsums(etcsums: List[types.EtcSum]) [error] -> Result[Map[Str]] {
  var mapped = {entry.path: entry.sha256 for entry in etcsums}
  mapped
}

## Exported PM declaration `load_etcsums`.
export proc load_etcsums(db: Path) [fs, error] -> Result[Map[Str]] {
  var mapped: Map[Str] = {}

  if fs.exists(fp"${db}/etcsums.json")? {
    let rows: List[types.EtcSum] = json.read(fp"${db}/etcsums.json")?

    for row in rows {
      mapped[row.path] = row.sha256
    }
  }

  mapped
}

## Exported PM declaration `load_metadata`.
export proc load_metadata(db: Path) [fs, error] -> Result[Record] {
  let metadata: Record = json.read(fp"${db}/metadata.json")?
  metadata
}

## Exported PM declaration `compressed_package_size`.
export pure compressed_package_size(size: Int) -> Str {
  let kib = (size + 1023) / 1024
  f"${kib}K"
}

## Exported PM declaration `collect_old_manifest_extra`.
export proc collect_old_manifest_extra(
  old_manifest: List[Path],
  new_manifest: List[Path],
) [error] -> Result[List[Path]] {
  var extra = [rel_path for rel_path in old_manifest if rel_path not in new_manifest]
  extra
}

## Exported PM declaration `collect_etcsums`.
export proc collect_etcsums(dest: Path, manifest: List[Path]) [fs, error] -> Result[List[types.EtcSum]] {
  var sums = []

  for rel_path in manifest {
    if util.is_etc_file(rel_path) {
      let meta = fs.metadata(fp"${dest}/${rel_path}")?

      if meta.kind == "file" {
        let sha256 = hash.sha256(fp"${dest}/${rel_path}")?.hex()
        sums = sums.push({path: rel_path.display(), sha256})
      }
    }
  }

  sums
}

## Exported PM declaration `validate_and_strip_package`.
export proc validate_and_strip_package(pkg: types.Package, dest: Path, manifest: List[Path]) [fs, process, error] {
  var declared: Map[types.FileKind] = {}
  var binaries = []

  for entry in pkg.filetree {
    let key = entry.path.display()

    if key == "" or key.starts_with("/") or key.starts_with("../") or "/../" in key {
      return Err(types.PmError.PackageContract(f"${pkg.name} declares an invalid filetree path ${key}"))
    }

    if declared.has(key) {
      return Err(types.PmError.PackageContract(f"${pkg.name} declares ${key} more than once"))
    }

    declared[key] = entry.kind

    if entry.kind == types.Binary {
      binaries = binaries.push(entry.path)
    }

    if entry.kind == types.Tree {
      if fs.metadata(fp"${dest}/${entry.path}")?.kind != "dir" {
        return Err(types.PmError.PackageContract(f"${pkg.name} declares ${key} as a tree, but it is not a directory"))
      }
    }
  }

  for rel_path in manifest {
    let key = rel_path.display()
    let path_value = fp"${dest}/${rel_path}"
    let actual_kind = fs.metadata(path_value)?.kind
    if ! declared.has(key) {
      var covered_by_tree = false

      for entry in pkg.filetree {
        let tree = entry.path.display()

        if entry.kind == types.Tree and key.starts_with(f"${tree}/") {
          covered_by_tree = true
        }
      }

      if ! covered_by_tree {
        return Err(types.PmError.PackageContract(f"${pkg.name} built undeclared file ${key}"))
      }

      if actual_kind == "symlink" {
        return Err(types.PmError.PackageContract(f"${pkg.name} symlink ${key} must be declared explicitly"))
      }

      match elf.inspect(path_value) {
        Ok(info) if info.type != "not-elf" => return Err(
          types.PmError.PackageContract(f"${pkg.name} ELF output ${key} must be declared as binary"),
        )
        Ok(_) => {}
        Err(_) => {}
      }

      continue
    }

    let declared_kind = declared.get(key)?

    if declared_kind == types.Tree {
      return Err(types.PmError.PackageContract(f"${pkg.name} filetree tree ${key} overlaps an output file"))
    }

    if declared_kind == types.Symlink {
      if actual_kind != "symlink" {
        return Err(types.PmError.PackageContract(f"${pkg.name} declares ${key} as a symlink, found ${actual_kind}"))
      }

      continue
    }

    if actual_kind != "file" {
      return Err(
        types.PmError.PackageContract(
          f"${pkg.name} declares ${key} as ${types.file_kind_text(declared_kind)}, found ${actual_kind}",
        ),
      )
    }

    match elf.inspect(path_value) {
      Ok(info) if info.type != "not-elf" and declared_kind == types.File => return Err(
        types.PmError.PackageContract(f"${pkg.name} ELF output ${key} must be declared as binary"),
      )
      Ok(info) if info.type == "not-elf" and declared_kind == types.Binary => return Err(
        types.PmError.PackageContract(f"${pkg.name} declares non-ELF output ${key} as binary"),
      )
      Ok(_) => {}
      Err(_) if declared_kind == types.Binary => return Err(
        types.PmError.PackageContract(f"${pkg.name} declares non-ELF output ${key} as binary"),
      )
      Err(_) => {}
    }
  }

  for entry in pkg.filetree {
    let key = entry.path.display()

    if entry.kind != types.Tree and ! fp"${dest}/${entry.path}".exists()? {
      return Err(types.PmError.PackageContract(f"${pkg.name} declares missing file ${key}"))
    }
  }

  if pkg.nostrip or binaries.len() == 0 {
    return
  }

  let strip = process.which("llvm-strip")?

  for rel_path in binaries {
    run $strip "--strip-unneeded" fp"${dest}/${rel_path}" ?
  }
}

## Exported PM declaration `collect_metadata_files`.
export proc collect_metadata_files(root: Path, manifest: List[Path]) [fs, error] -> Result[List[types.ArtifactEntry]] {
  var files: List[types.ArtifactEntry] = []
  let root_handle = fs.open_root(root)?
  defer fs.close_root(root_handle)

  for rel_path in manifest {
    match fs.root_readlink(root_handle, rel_path) {
      Ok(target) => {
        files = files.push(
          {path: rel_path.display(), kind: types.Symlink, mode: 0o777, sha256: "", target: target.display()},
        )

        continue
      }
      Err(_) => {}
    }

    let meta = fs.root_metadata(root_handle, rel_path)?
    var sha256 = ""

    if meta.kind == "file" {
      sha256 = fs.root_read(root_handle, rel_path)?.sha256().hex()
    }

    var kind = types.File

    match meta.kind {
      "file" => kind = types.File
      "dir" => kind = types.Tree
      _ => return Err(types.PmError.PackageContract(f"metadata cannot represent ${rel_path.display()} as ${meta.kind}"))
    }
    files = files.push({path: rel_path.display(), kind, mode: meta.mode % 4096, sha256, target: ""})
  }

  files
}

## Exported PM declaration `collect_artifact_entries`.
## Captures files, symlinks, and explicitly archived empty directories for immutable artifact metadata.
export proc collect_artifact_entries(root: Path) [fs, error] -> Result[List[types.ArtifactEntry]] {
  var entries: List[Path] = []
  let root_text = root.display()

  for entry in fs.walk(root) {
    var include = entry.kind == "file" or entry.kind == "symlink"

    if entry.kind == "dir" and entry.path.display() != root_text and dir_empty(entry.path)? {
      include = true
    }

    if include {
      entries = entries.push(entry.path.strip_prefix(root)?)
    }
  }

  collect_metadata_files(root, entries |> sort-by .display())?
}

## Exported PM declaration `metadata_files_sha256`.
export proc metadata_files_sha256(pkg: types.Package, files: List[types.ArtifactEntry]) [error] -> Result[Str] {
  var body = f"""name	${pkg.name}
ver	${pkg.ver}
deps	${pkg.deps.join(" ")}
mkdeps_host	${pkg.mkdeps_host.join(" ")}
"""

  if pkg.mkdeps_target.len() > 0 {
    body = f"""${body}mkdeps_target	${pkg.mkdeps_target.join(" ")}
"""
  }

  for entry in pkg.filetree {
    body = f"""${body}filetree	${entry.path.display()}	${types.file_kind_text(entry.kind)}
"""
  }

  for file in files {
    body = f"""${body}${file.path}	${types.file_kind_text(file.kind)}	${file.mode}	${file.sha256}	${file.target}
"""
  }

  bytes.from_text(body).sha256().hex()
}

## Exported PM declaration `write_package_metadata`.
export proc write_package_metadata(path_value: Path, arch: Str, item: types.BuiltPackage) [fs, error] {
  fs.mkdir(path_value.parent)?
  let manifest = collect_manifest_text(item.manifest)?

  json.write(
    path_value,
    {
      arch,
      name: item.pkg.name,
      ver: item.pkg.ver,
      rel: item.pkg.rel,
      deps: item.pkg.deps,
      mkdeps_host: item.pkg.mkdeps_host,
      mkdeps_target: item.pkg.mkdeps_target,
      filetree: [{path: entry.path.display(), kind: types.file_kind_text(entry.kind)} for entry in item.pkg.filetree],
      manifest,
      metadata_sha256: item.metadata_sha256,
      package_kind: types.package_kind_text(item.pkg.kind),
      files: [
        {
          path: entry.path,
          kind: types.file_kind_text(entry.kind),
          mode: entry.mode,
          sha256: entry.sha256,
          target: entry.target,
        }
        for entry in item.metadata_files
      ],
    },
  )?
}

## Exported PM declaration `load_installed_owners`.
export proc load_installed_owners(root: Path) [fs, error] -> Result[Map[Str]] {
  var owners: Map[Str] = {}
  let packages_db = util.packages_db_path(root)

  if ! fs.exists(packages_db)? {
    return owners
  }

  let entries = fs.children(packages_db)?

  for entry in entries {
    if entry.kind == "dir" {
      let manifest = load_manifest(entry.path)?

      for rel_path in manifest {
        owners[rel_path.display()] = entry.name
      }
    }
  }

  owners
}

## Exported PM declaration `ensure_installable`.
export proc ensure_installable(
  root: Path,
  pkg: types.Package,
  manifest: List[Path],
  installed_owners: Map[Str],
) [fs, error] {
  for rel_path in manifest {
    let key = rel_path.display()

    if installed_owners.has(key) {
      let owner = installed_owners.get(key)?

      if owner != pkg.name {
        return Err(types.PmError.PackageConflict(f"${pkg.name} conflicts with ${owner}: ${key}"))
      }
    } else if fs.exists(fp"${root}/${rel_path}")? and ! util.is_etc_file(rel_path) {
      let root_str = root.display()
      var msg = f"${pkg.name} would overwrite unowned ${key} in root ${root_str}"

      if root_str.ends_with("/.world/root") or root_str.ends_with("/.world/build-root") {
        let cache_dir = root.parent.parent

        msg = f"""${msg}
stale world-plan cache: delete ${cache_dir.display()} to reset"""
      }

      return Err(types.PmError.DirtyFilesystem(msg))
    }
  }
}

## Exported PM declaration `install_etc_file`.
export proc install_etc_file(
  source_root: FsRoot,
  source: Path,
  dest_root: FsRoot,
  dest: Path,
  mode: Int,
  key: Str,
  old_sums: Map[Str],
  new_sums: Map[Str],
) [fs, error] {
  let new_sum = new_sums.get(key)?
  var old_sum = ""

  if old_sums.has(key) {
    let value = old_sums.get(key)?
    old_sum = value
  }

  var sys_sum = ""

  if fs.root_exists(dest_root, dest)? {
    sys_sum = fs.root_read(dest_root, dest)?.sha256().hex()
  }

  if old_sum == new_sum and new_sum != sys_sum {
    return
  }

  if sys_sum == "" or old_sum == sys_sum or sys_sum == new_sum {
    fs.root_install_file(source_root, source, dest_root, dest, mode, overwrite: true)?
    return
  }

  fs.root_install_file(source_root, source, dest_root, fp"${dest.parent}/${dest.name}.new", mode, overwrite: true)?
}

## Exported PM declaration `install_manifest_entries`.
export proc install_manifest_entries(
  root: Path,
  stage: Path,
  pkg: types.Package,
  manifest: List[Path],
  old_sums: Map[Str],
  new_sums: Map[Str],
  installed_owners: Map[Str],
) [fs, error] {
  let source_root = fs.open_root(stage)?
  defer fs.close_root(source_root)
  let dest_root = fs.open_root(root)?
  defer fs.close_root(dest_root)

  for rel_path in manifest {
    let key = rel_path.display()
    var overwrite = false

    if installed_owners.has(key) {
      let owner = installed_owners.get(key)?

      if owner == pkg.name {
        overwrite = true
      }
    }

    match fs.root_readlink(source_root, rel_path) {
      Ok(target) => {
        fs.root_symlink(dest_root, target, rel_path, true, overwrite)?
        continue
      }
      Err(_) => {}
    }

    let metadata = fs.root_metadata(source_root, rel_path)?

    if metadata.kind == "file" {
      let file_mode = metadata.mode % 4096

      if util.is_etc_file(rel_path) {
        install_etc_file(source_root, rel_path, dest_root, rel_path, file_mode, key, old_sums, new_sums)?
      } else {
        fs.root_install_file(source_root, rel_path, dest_root, rel_path, file_mode, overwrite: overwrite)?
      }
    }
  }
}

## Exported PM declaration `dir_empty`.
export proc dir_empty(path_value: Path) [fs, error] -> Result[Bool] {
  for _ in fs.ls(path_value)? {
    return false
  }

  true
}

## Exported PM declaration `direct_extract_package`.
export proc direct_extract_package(
  ctx: types.PmContext,
  pkg: types.Package,
  tarball: Path,
  manifest: List[Path],
  etcsums: List[types.EtcSum],
  installed_owners: Map[Str],
) [fs, error] {
  ensure_installable(ctx.root, pkg, manifest, installed_owners)?
  archive.tar_extract(tarball, ctx.root, 0, "auto", true)?
  write_package_db(ctx.root, pkg, manifest, etcsums)?
}

## Exported PM declaration `collect_removable_manifest`.
export proc collect_removable_manifest(
  root: Path,
  manifest: List[Path],
  etcsums: Map[Str],
) [fs, error] -> Result[List[Path]] {
  var removable = []
  let root_handle = fs.open_root(root)?
  defer fs.close_root(root_handle)

  for rel_path in manifest {
    let key = rel_path.display()

    if util.is_etc_file(rel_path) and etcsums.has(key) and fs.root_exists(root_handle, rel_path)? {
      let expected = etcsums.get(key)?

      if fs.root_read(root_handle, rel_path)?.sha256().hex() == expected {
        removable = removable.push(rel_path)
      }
    } else {
      removable = removable.push(rel_path)
    }
  }

  removable
}

## Exported PM declaration `write_package_db`.
export proc write_package_db(
  root: Path,
  pkg: types.Package,
  manifest: List[Path],
  etcsums: List[types.EtcSum],
) [fs, error] {
  let db = util.package_db_path(root, pkg.name)
  fs.mkdir(db)?
  let manifest_text = collect_manifest_text(manifest)?
  json.write(fp"${db}/manifest.json", manifest_text)?
  json.write(fp"${db}/etcsums.json", etcsums)?

  json.write(
    fp"${db}/metadata.json",
    {
      name: pkg.name,
      ver: pkg.ver,
      rel: pkg.rel,
      deps: pkg.deps,
      mkdeps_host: pkg.mkdeps_host,
      mkdeps_target: pkg.mkdeps_target,
      package_kind: types.package_kind_text(pkg.kind),
      filetree: [{path: entry.path.display(), kind: types.file_kind_text(entry.kind)} for entry in pkg.filetree],
      nostrip: pkg.nostrip,
      dir: pkg.dir.display(),
    },
  )?
}

## Exported PM declaration `call_pkg_hook`.
export proc call_pkg_hook(pkg: types.Package, hook_name: Str, root: Path) [fs, process, env, error] {
  recipe.call_hook(pkg, hook_name, root)?
}

## Exported PM declaration `call_installed_hook`.
export proc call_installed_hook(metadata: Record, hook_name: Str, root: Path) [fs, process, env, error] {
  recipe.call_recipe_installed_hook(metadata, hook_name, root)?
}

## Exported PM declaration `load_package_dirs`.
export proc load_package_dirs(dirs: List[Path]) [fs, env, error] -> Result[List[types.Package]] {
  var packages = []
  var seen: Map[Bool] = {}

  for dir in dirs {
    let pkg = recipe.load_package(dir)?

    if seen.has(pkg.name) {
      return Err(types.PmError.PackageContract(f"duplicate package ${pkg.name}"))
    }

    seen[pkg.name] = true
    packages = packages.push(pkg)
  }

  packages
}

## Exported PM declaration `order_packages`.
export proc order_packages(
  root: Path,
  packages: List[types.Package],
  allow_installed_deps: Bool,
) [fs, error] -> Result[List[types.Package]] {
  var local_names: Map[Bool] = {}
  var available_names: List[Str] = []

  for pkg in packages {
    local_names[pkg.name] = true
  }

  for pkg in packages {
    for dependency in pkg.deps {
      if ! local_names.get(dependency, false) {
        if ! allow_installed_deps or ! fs.exists(util.package_db_path(root, dependency))? {
          return Err(types.PmError.MissingDependency(f"${pkg.name} depends on missing ${dependency}"))
        }

        available_names = available_names.push(dependency)
      }
    }

    for dependency in pkg.mkdeps_host.extend(pkg.mkdeps_target) {
      if ! local_names.get(dependency, false) {
        available_names = available_names.push(dependency)
      }
    }
  }

  let value = catalog.from_packages(root, packages, available_names)?
  let edges = graph.edges(value, policy.aarch64_docker())?
  let runtime_edges = [edge for edge in edges if edge.kind == types.Runtime]
  let levels = graph.topological_levels(catalog.package_names(value), runtime_edges)?
  let by_name = catalog.package_map(value)
  var ordered: List[types.Package] = []

  for level in levels {
    for name in level {
      if by_name.has(name) {
        let pkg: types.Package = by_name.get(name)?
        ordered = ordered.push(pkg)
      }
    }
  }

  ordered
}

## Exported PM declaration `filter_packages_by_names`.
export proc filter_packages_by_names(
  packages: List[types.Package],
  names: List[Str],
) [error] -> Result[List[types.Package]] {
  var selected = [pkg for pkg in packages if pkg.name in names]
  selected
}

## Exported PM declaration `collect_upgrade_names`.
export proc collect_upgrade_names(root: Path, packages: List[types.Package]) [fs, error] -> Result[List[Str]] {
  var names = []

  for pkg in packages {
    let db = util.package_db_path(root, pkg.name)

    if fs.exists(db)? {
      let metadata = load_metadata(db)?
      let ver: Str = metadata.get("ver")?
      let rel: Str = metadata.get("rel")?

      if ver != pkg.ver or rel != pkg.rel {
        names = names.push(pkg.name)
      }
    }
  }

  if "pm" in names {
    return ["pm"]
  }

  names
}

## Exported PM declaration `collect_local_index`.
export pure collect_local_index(packages: List[types.Package]) -> Result[List[types.PackageIndex]] {
  let index = [
    {
      name: pkg.name,
      ver: pkg.ver,
      rel: pkg.rel,
      deps: pkg.deps,
      mkdeps_host: pkg.mkdeps_host,
      mkdeps_target: pkg.mkdeps_target,
    }
    for pkg in packages
  ]

  index
}

## Exported PM declaration `load_built_package_from_dest`.
export proc load_built_package_from_dest(
  pkg: types.Package,
  id: Str,
  tarball: Path,
  dest: Path,
) [fs, error] -> Result[types.BuiltPackage] {
  let db = util.package_db_path(dest, pkg.name)
  let manifest = load_manifest(db)?
  let etcsums: List[types.EtcSum] = json.read(fp"${db}/etcsums.json")?
  let metadata_files = collect_artifact_entries(dest)?
  let metadata_sha256 = metadata_files_sha256(pkg, metadata_files)?

  return {
    pkg,
    id,
    tarball,
    manifest,
    etcsums,
    metadata_sha256,
    metadata_files,
  }
}

## Exported PM declaration `write_local_index`.
export proc write_local_index(out: Path, packages: List[types.Package]) [fs, error] {
  fs.mkdir(out)?
  let index = collect_local_index(packages)?
  json.write(fp"${out}/index.json", index)?

  for pkg in packages {
    print ${pkg.name} util.version_id(pkg.ver, pkg.rel) "indexed"
  }
}

## Exported PM declaration `print_package_checksums`.
export proc print_package_checksums(work: Path, pkg: types.Package) [fs, net, process, env, time, error] {
  let arch = util.machine_arch()?
  let generated = sources.generate_checksums_for(work, pkg, arch)?

  for checksum in generated {
    print ${pkg.name} $checksum
  }
}

## Exported PM declaration `update_package_checksums`.
export proc update_package_checksums(work: Path, pkg: types.Package) [fs, net, process, env, time, error] {
  let updates = sources.collect_checksum_updates(work, pkg)?

  for update in updates {
    sources.write_checksum_field(pkg, update.field, update.values)?
    print ${pkg.name} ${update.field} updated
  }
}

## Exported PM declaration `download_package_sources`.
export proc download_package_sources(work: Path, out: Path, pkg: types.Package) [fs, net, process, env, time, error] {
  let id = util.package_id(pkg.name, pkg.ver, pkg.rel)
  let src = fp"${work}/download/${id}"
  fs.remove(src, missing_ok: true)?
  fs.mkdir(src)?
  sources.prepare_package_source_tree(work, out, pkg, src, false, true, true)?
  print ${pkg.name} "sources" "downloaded"
}
