use extensions
use sources
use types
use util

export pure collect_manifest_text(manifest: List[Path]) -> Result[List[Str]] {
  let lines = [rel_path.display() for rel_path in manifest]
  lines
}

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

export proc map_etcsums(etcsums: List[EtcSum]) [error] -> Result[Map[Str]] {
  var mapped = {entry.path: entry.sha256 for entry in etcsums}
  mapped
}

export proc load_etcsums(db: Path) [fs, error] -> Result[Map[Str]] {
  var mapped: Map[Str] = {}

  if fs.exists(fp"${db}/etcsums.json")? {
    let rows: List[EtcSum] = json.read(fp"${db}/etcsums.json")?

    for row in rows {
      mapped[row.path] = row.sha256
    }
  }

  mapped
}

export proc load_metadata(db: Path) [fs, error] -> Result[Record] {
  let metadata: Record = json.read(fp"${db}/metadata.json")?
  metadata
}

export proc load_extract_install(db: Path) [fs, error] -> Result[Bool] {
  if ! fs.exists(fp"${db}/metadata.json")? {
    return false
  }

  let metadata = load_metadata(db)?

  if metadata.has("extract_install") {
    let extract_install: Bool = metadata.get("extract_install")?
    return extract_install
  }

  false
}

export pure package_with_extract_install(pkg: Package, extract_install: Bool) -> Package {
  {
    dir: pkg.dir,
    exports: pkg.exports,
    name: pkg.name,
    ver: pkg.ver,
    rel: pkg.rel,
    deps: pkg.deps,
    mkdeps: pkg.mkdeps,
    target_build_deps: pkg.target_build_deps,
    sources: pkg.sources,
    checksums: pkg.checksums,
    nostrip: pkg.nostrip,
    extract_install,
  }
}

export proc collect_old_manifest_extra(
  old_manifest: List[Path],
  new_manifest: List[Path],
) [error] -> Result[List[Path]] {
  var extra = [rel_path for rel_path in old_manifest if rel_path not in new_manifest]
  extra
}

export proc collect_etcsums(dest: Path, manifest: List[Path]) [fs, error] -> Result[List[EtcSum]] {
  var sums = []

  for rel_path in manifest {
    if is_etc_file(rel_path) {
      let meta = fs.metadata(fp"${dest}/${rel_path}")?

      if meta.kind == "file" {
        let sha256 = hash.sha256(fp"${dest}/${rel_path}")?.hex()
        sums = sums.push({path: rel_path.display(), sha256})
      }
    }
  }

  sums
}

export proc collect_metadata_files(root: Path, manifest: List[Path]) [fs, error] -> Result[List[Record]] {
  var files = []
  let root_handle = fs.open_root(root)?
  defer fs.close_root(root_handle)

  for rel_path in manifest {
    match fs.root_readlink(root_handle, rel_path) {
      Ok(target) => {
        files = files.push(
          {path: rel_path.display(), kind: "symlink", mode: 0o777, sha256: "", target: target.display()},
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

    files = files.push({path: rel_path.display(), kind: meta.kind, mode: meta.mode % 4096, sha256, target: ""})
  }

  files
}

export proc metadata_files_sha256(pkg: Package, files: List[Record]) [error] -> Result[Str] {
  var body = f"""name	${pkg.name}
ver	${pkg.ver}
deps	${pkg.deps.join(" ")}
mkdeps	${pkg.mkdeps.join(" ")}
"""

  if pkg.target_build_deps.len() > 0 {
    body = f"""${body}target_build_deps	${pkg.target_build_deps.join(" ")}
"""
  }

  for file in files {
    let path_text: Str = file.get("path")?
    let kind: Str = file.get("kind")?
    let mode: Int = file.get("mode")?
    let sha256: Str = file.get("sha256")?
    let target: Str = file.get("target")?

    body = f"""${body}${path_text}	${kind}	${mode}	${sha256}	${target}
"""
  }

  bytes.from_text(body).sha256().hex()
}

export proc write_package_metadata(path_value: Path, arch: Str, item: BuiltPackage) [fs, error] {
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
      mkdeps: item.pkg.mkdeps,
      target_build_deps: item.pkg.target_build_deps,
      manifest,
      metadata_sha256: item.metadata_sha256,
      files: item.metadata_files,
    },
  )?
}

export proc load_installed_owners(root: Path) [fs, error] -> Result[Map[Str]] {
  var owners: Map[Str] = {}
  let packages_db = packages_db_path(root)

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

export proc ensure_installable(root: Path, pkg: Package, manifest: List[Path], installed_owners: Map[Str]) [fs, error] {
  for rel_path in manifest {
    let key = rel_path.display()

    if installed_owners.has(key) {
      let owner = installed_owners.get(key)?

      if owner != pkg.name {
        return Err(PmError.PackageConflict(f"${pkg.name} conflicts with ${owner}: ${key}"))
      }
    } else if fs.exists(fp"${root}/${rel_path}")? and ! is_etc_file(rel_path) {
      let root_str = root.display()
      var msg = f"${pkg.name} would overwrite unowned ${key} in root ${root_str}"

      if root_str.ends_with("/.world/root") or root_str.ends_with("/.world/build-root") {
        let cache_dir = root.parent.parent

        msg = f"""${msg}
stale world-plan cache: delete ${cache_dir.display()} to reset"""
      }

      return Err(PmError.DirtyFilesystem(msg))
    }
  }
}

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

export proc install_manifest_entries(
  root: Path,
  stage: Path,
  pkg: Package,
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

      if is_etc_file(rel_path) {
        install_etc_file(source_root, rel_path, dest_root, rel_path, file_mode, key, old_sums, new_sums)?
      } else {
        fs.root_install_file(source_root, rel_path, dest_root, rel_path, file_mode, overwrite: overwrite)?
      }
    }
  }
}

export proc dir_empty(path_value: Path) [fs, error] -> Result[Bool] {
  for _ in fs.ls(path_value)? {
    return false
  }

  true
}

export proc direct_extract_package(
  ctx: PmContext,
  pkg: Package,
  tarball: Path,
  manifest: List[Path],
  etcsums: List[EtcSum],
  installed_owners: Map[Str],
) [fs, error] {
  ensure_installable(ctx.root, pkg, manifest, installed_owners)?
  archive.tar_extract(tarball, ctx.root, 0, "auto", true)?
  write_package_db(ctx.root, pkg, manifest, etcsums)?
}

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

    if is_etc_file(rel_path) and etcsums.has(key) and fs.root_exists(root_handle, rel_path)? {
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

export proc write_package_db(root: Path, pkg: Package, manifest: List[Path], etcsums: List[EtcSum]) [fs, error] {
  let db = package_db_path(root, pkg.name)
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
      mkdeps: pkg.mkdeps,
      target_build_deps: pkg.target_build_deps,
      nostrip: pkg.nostrip,
      extract_install: pkg.extract_install,
      dir: pkg.dir.display(),
    },
  )?
}

export proc call_pkg_hook(pkg: Package, hook_name: Str, root: Path) [error] {
  let exports = pkg.exports

  if exports.has(hook_name) {
    let hook: Proc = exports.get(hook_name)?
    hook.call(root)?
  }
}

export proc call_installed_hook(metadata: Record, hook_name: Str, root: Path) [fs, error] {
  if ! metadata.has("dir") {
    return
  }

  let dir_text: Str = metadata.get("dir")?
  let pkgbuild = fp"${fp"${dir_text}"}/PKGBUILD.xsh"

  if ! fs.exists(pkgbuild)? {
    return
  }

  let exports = module.load(pkgbuild)?

  if exports.has(hook_name) {
    let hook: Proc = exports.get(hook_name)?
    hook.call(root)?
  }
}

export proc load_package_dirs(dirs: List[Path]) [fs, env, error] -> Result[List[Package]] {
  var packages = []
  var seen: Map[Bool] = {}

  for dir in dirs {
    let pkgbuild = fp"${dir}/PKGBUILD.xsh"
    let exports = module.load(pkgbuild).context("package-load", pkgbuild.display())?
    let name: Str = exports.get("name").context("package-load", pkgbuild.display())?
    let ver: Str = exports.get("ver")?
    let rel: Str = exports.get("rel")?
    let deps: List[Str] = exports.get("deps")?
    let mkdeps: List[Str] = exports.get("mkdeps")?
    var target_build_deps = []
    let pkg_sources: List[Path] = exports.get("sources")?
    let base_checksums: List[Str] = exports.get("checksums")?
    let checksums = select_checksums(exports, base_checksums)?
    var nostrip = false
    var extract_install = false

    if exports.has("target_build_deps") {
      target_build_deps = exports.get("target_build_deps")?
    }

    if exports.has("nostrip") {
      let value: Bool = exports.get("nostrip")?
      nostrip = value
    }

    if exports.has("extract_install") {
      let value: Bool = exports.get("extract_install")?
      extract_install = value
    }

    if name == "" {
      return Err(PmError.PackageContract(f"${dir.display()} exports an empty name"))
    }

    if ver == "" or rel == "" {
      return Err(PmError.PackageContract(f"${name} exports an empty version or release"))
    }

    if pkg_sources.len() != checksums.len() {
      return Err(PmError.PackageContract(f"${name} source/checksum count mismatch"))
    }

    if seen.has(name) {
      return Err(PmError.PackageContract(f"duplicate package ${name}"))
    }

    seen[name] = true

    packages = packages.push({
      dir,
      exports,
      name,
      ver,
      rel,
      deps,
      mkdeps,
      target_build_deps,
      sources: pkg_sources,
      checksums,
      nostrip,
      extract_install,
    })
  }

  packages
}

export proc order_packages(
  root: Path,
  packages: List[Package],
  allow_installed_deps: Bool,
) [fs, error] -> Result[List[Package]] {
  var ordered = []
  var by_name: Map[Int] = {}
  var pkg_index = 0

  for pkg in packages {
    by_name[pkg.name] = pkg_index
    pkg_index += 1
  }

  var added: Map[Bool] = {}

  while ordered.len() < packages.len() {
    var progressed = false

    for pkg in packages {
      if ! added.get(pkg.name, false) {
        var ready = true

        for dep in pkg.deps {
          if ! by_name.has(dep) {
            if ! allow_installed_deps or ! fs.exists(package_db_path(root, dep))? {
              return Err(PmError.MissingDependency(f"${pkg.name} depends on missing ${dep}"))
            }
          } else if ! added.get(dep, false) {
            ready = false
          }
        }

        if ready {
          ordered = ordered.push(pkg)
          added[pkg.name] = true
          progressed = true
        }
      }
    }

    if ! progressed {
      return Err(PmError.DependencyCycle("package dependency graph did not make progress"))
    }
  }

  ordered
}

export proc filter_packages_by_names(packages: List[Package], names: List[Str]) [error] -> Result[List[Package]] {
  var selected = [pkg for pkg in packages if pkg.name in names]
  selected
}

export proc collect_upgrade_names(root: Path, packages: List[Package]) [fs, error] -> Result[List[Str]] {
  var names = []

  for pkg in packages {
    let db = package_db_path(root, pkg.name)

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

export pure collect_local_index(packages: List[Package]) -> Result[List[PackageIndex]] {
  let index = [{
    name: pkg.name,
    ver: pkg.ver,
    rel: pkg.rel,
    deps: pkg.deps,
    mkdeps: pkg.mkdeps,
    target_build_deps: pkg.target_build_deps,
  } for pkg in packages]

  index
}

export proc load_built_package_from_dest(
  pkg: Package,
  id: Str,
  tarball: Path,
  dest: Path,
) [fs, error] -> Result[BuiltPackage] {
  let db = package_db_path(dest, pkg.name)
  let manifest = load_manifest(db)?
  let etcsums: List[EtcSum] = json.read(fp"${db}/etcsums.json")?
  let metadata_files = collect_metadata_files(dest, manifest)?
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

export proc write_local_index(out: Path, packages: List[Package]) [fs, error] {
  fs.mkdir(out)?
  let index = collect_local_index(packages)?
  json.write(fp"${out}/index.json", index)?

  for pkg in packages {
    print ${pkg.name} version_id(pkg.ver, pkg.rel) "indexed"
  }
}

export proc print_package_checksums(work: Path, pkg: Package) [fs, net, process, env, time, error] {
  let arch = machine_arch()?
  let generated = generate_checksums_for(work, pkg, arch, pkg.checksums)?

  for checksum in generated {
    print ${pkg.name} $checksum
  }
}

export proc update_package_checksums(work: Path, pkg: Package) [fs, net, process, env, time, error] {
  let updates = collect_checksum_updates(work, pkg)?

  for update in updates {
    write_checksum_field(pkg, update.field, update.values)?
    print ${pkg.name} ${update.field} updated
  }
}

export proc download_package_sources(work: Path, out: Path, pkg: Package) [fs, net, process, env, time, error] {
  let id = package_id(pkg.name, pkg.ver, pkg.rel)
  let src = fp"${work}/download/${id}"
  fs.remove(src, missing_ok: true)?
  fs.mkdir(src)?
  prepare_package_source_tree(work, out, pkg, src, false, true, true)?
  print ${pkg.name} "sources" "downloaded"
}
