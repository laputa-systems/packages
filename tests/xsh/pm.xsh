use pm.buildroot
use pm.configure
use pm.elfdeps as pm_elfdeps
use pm.local as pm_local
use pm.make
use pm.world as pm_world

pure xsh_bin() -> Path {
  return p"xsh"
}

pure make_helper_task(
  name: Str,
  cwd: Path,
  outputs: List[Path],
  inputs: List[Path],
  deps: List[Str],
  helper: Path,
  mode: Str,
  args: List[Str],
  stamp: Path,
  depfile: Path = p"",
) -> make.MakeTask {
  return {
    name: name,
    outputs: outputs,
    inputs: inputs,
    deps: deps,
    argv: [xsh_bin().display(), helper.display(), "--", mode].extend(args),
    cwd: cwd,
    env: {},
    depfile: depfile,
    stamp: stamp,
  }
}

pure baseinit_dir() -> Path {
  return p"tests/xsh/fixtures/baseinit"
}

pure dep_dir() -> Path {
  return p"tests/xsh/fixtures/dep"
}

pure app_dir() -> Path {
  return p"tests/xsh/fixtures/app"
}

pure tool_v1_dir() -> Path {
  return p"tests/xsh/fixtures/tool-v1"
}

pure tool_v2_dir() -> Path {
  return p"tests/xsh/fixtures/tool-v2"
}

pure source_pkg_dir() -> Path {
  return p"tests/xsh/fixtures/source-pkg"
}

pure extract_tree_dir() -> Path {
  return p"tests/xsh/fixtures/extract-tree"
}

pure remote_app_dir() -> Path {
  return p"tests/xsh/fixtures/remote-app"
}

pure remote_meta_dir() -> Path {
  return p"tests/xsh/fixtures/remote-meta"
}

pure world_lib_dir() -> Path {
  return p"tests/xsh/fixtures/world-lib"
}

pure world_app_dir() -> Path {
  return p"tests/xsh/fixtures/world-app"
}

pure world_pm_dir() -> Path {
  return p"tests/xsh/fixtures/world-pm"
}

proc fixture_arch() [env, error] -> Result[Str] {
  let os = system.uname()?

  if os.machine == "arm64" {
    return "aarch64"
  }

  os.machine
}

proc single_world_cache(home: Path) [fs, error] -> Result[Path] {
  let root = fp"${home}/.cache/laputa"
  var found = [entry.path for entry in fs.children(root)? if entry.kind == "dir" and entry.name.starts_with("world-")]
  test.eq(found.len(), 1)?
  found[0]
}

pure waterfox_forbidden_pm_info_terms() -> List[Str] {
  [
    "dwl",
    "seatd",
    "Mesa",
    "Wayland",
    "xkbcommon",
    "ALSA",
    "PipeWire",
    "PulseAudio",
    "DBus",
    "portals",
    "X11",
    "XCB",
    "GLX",
    "GTK",
    "fontconfig",
    "freetype",
    "libva",
  ]
}

proc test_pm_baseinit_smoke(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let output = run.text xsh_bin() pm.xsh -- $root $work $out baseinit_dir() ?
  test.contains(output, "baseinit baseinit-2.0.0-1 build: 5 files")?
  test.contains(output, "baseinit 5 8 installed")?
  test.contains(output, "baseinit 5 removed")?
  test.ok(fp"${out}/baseinit-2.0.0-1.tar.gz".exists()?)?
  test.eq(fp"${root}/etc/inittab".exists()?, false)?
}

proc test_pm_preserves_existing_etc_files(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  fs.mkdir(fp"${root}/etc")?

  fs.write(
    fp"${root}/etc/inittab",
    """custom
""",
  )?

  let output = run.text xsh_bin() pm.xsh -- $root $work $out baseinit_dir() ?
  test.contains(output, "baseinit 4 removed")?

  test.eq(
    fp"${root}/etc/inittab".read_text()?,
    """custom
""",
  )?

  test.ok(fp"${root}/etc/inittab.new".exists()?)?
}

proc test_pm_rejects_file_conflicts(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  fs.mkdir(fp"${root}/usr/lib/init")?

  fs.write(
    fp"${root}/usr/lib/init/rc.lib",
    """existing
""",
  )?

  let status = run.status xsh_bin() pm.xsh -- $root $work $out baseinit_dir() 2> /dev/null
  test.eq(status.ok, false)?

  test.eq(
    fp"${root}/usr/lib/init/rc.lib".read_text()?,
    """existing
""",
  )?
}

proc test_pm_rejects_unowned_non_etc_files(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let err = test.temp_path(ctx, name: "pm.err")
  fs.mkdir(fp"${root}/usr/share")?

  fs.write(
    fp"${root}/usr/share/dep.txt",
    """stale
""",
  )?

  let status = run.status xsh_bin() pm.xsh -- install $root $work $out dep_dir() 2> $err
  test.eq(status.ok, false)?
  test.contains(err.read_text()?, "dep would overwrite unowned usr/share/dep.txt")?

  test.eq(
    fp"${root}/usr/share/dep.txt".read_text()?,
    """stale
""",
  )?
}

proc test_pm_info_waterfox_bin_excludes_session_stack(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "waterfox-info-root")?
  let work = test.temp_dir(ctx, name: "waterfox-info-work")?
  let out = test.temp_dir(ctx, name: "waterfox-info-out")?
  let db = fp"${root}/var/lib/xsh-pm/packages/waterfox-bin"
  let no_mkdeps_host = []
  let no_etcsums = []
  fs.mkdir(db)?

  json.write(
    fp"${db}/metadata.json",
    {
      name: "waterfox-bin",
      ver: "140.11.0esr",
      rel: "1",
      deps: ["musl", "ca-certificates"],
      mkdeps_host: no_mkdeps_host,
      nostrip: true,
      dir: "repo/waterfox-bin",
    },
  )?

  json.write(fp"${db}/manifest.json", ["opt/waterfox/waterfox-bin", "usr/bin/waterfox"])?
  json.write(fp"${db}/etcsums.json", no_etcsums)?
  let info = run.text xsh_bin() pm.xsh -- info $root $work $out waterfox-bin ?
  test.contains(info, "waterfox-bin 140.11.0esr-1")?
  test.contains(info, "deps musl ca-certificates")?
  test.contains(info, "mkdeps_host")?

  for term in waterfox_forbidden_pm_info_terms() {
    test.eq(term in info, false, message: f"pm info unexpectedly contained ${term}")?
  }
}

proc test_pm_install_remove_lifecycle(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let install_out = run.text xsh_bin() pm.xsh -- install $root $work $out dep_dir() app_dir() ?
  test.contains(install_out, "dep dep-1.0.0-1 build: 1 files")?
  test.contains(install_out, "app app-1.0.0-1 build: 1 files")?

  test.eq(
    fp"${root}/usr/share/app.txt".read_text()?,
    """app
""",
  )?

  let list_out = run.text xsh_bin() pm.xsh -- list $root $work $out ?
  test.contains(list_out, "dep")?
  test.contains(list_out, "app")?
  let info_out = run.text xsh_bin() pm.xsh -- info $root $work $out dep ?
  test.contains(info_out, "dep")?
  test.contains(info_out, "1.0.0")?
  let tree_out = run.text xsh_bin() pm.xsh -- tree $root $work $out app ?

  test.eq(
    tree_out,
    """app
`-- dep
""",
  )?

  let full_tree_out = run.text xsh_bin() pm.xsh -- tree $root $work $out ?
  test.eq(full_tree_out, tree_out)?
  run.text xsh_bin() pm.xsh -- remove $root $work $out app ?
  run.text xsh_bin() pm.xsh -- remove $root $work $out dep ?
  test.eq(fp"${root}/usr/share/app.txt".exists()?, false)?
}

proc test_pm_extract_install_preserves_tree_entries(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "extract-root")?
  let work = test.temp_dir(ctx, name: "extract-work")?
  let out = test.temp_dir(ctx, name: "extract-out")?
  let output = run.text xsh_bin() pm.xsh -- install $root $work $out extract_tree_dir() ?
  test.contains(output, "extract-tree extract-tree-1.0.0-1 build: 3 files")?
  test.contains(output, "extract-tree 3 ")?

  test.eq(
    fp"${root}/etc/extract-tree.conf".read_text()?,
    """extract-tree
""",
  )?

  test.eq(fp"${root}/empty-dir/.keep".exists()?, false)?
  test.eq(fp"${root}/bin".metadata()?.kind, "symlink")?
  test.eq(fp"${root}/bin".readlink()?.display(), "usr/bin")?
  test.eq(fp"${root}/usr/bin/extract-tree".metadata()?.mode % 4096, 0o755)?
}

proc test_pm_package_build_uses_configure_helpers(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let pkg = test.temp_dir(ctx, name: "configured-pkg")?
  fs.mkdir(fp"${pkg}/files")?

  fs.write(
    fp"${pkg}/files/config.h.in",
    """#undef ENABLE_CONFIGURED
#undef DISABLED_FEATURE
""",
  )?

  fs.write(
    fp"${pkg}/files/message.in",
    """name=@NAME@
mode=@MODE@
literal=@UNKNOWN@
""",
  )?

  var defines: Map[Str] = {}
  defines["ENABLE_CONFIGURED"] = "1"
  configure.config_h(fp"${pkg}/files/config.h.in", fp"${pkg}/generated/config.h", defines)?

  configure.substitute(
    fp"${pkg}/files/message.in",
    fp"${pkg}/generated/message.txt",
    [["NAME", "configured-pkg"], ["MODE", "install"]],
  )?

  fs.write(
    fp"${pkg}/PKGBUILD.xsh",
    r"""export let name = "configured-pkg"
export let ver = "1.0.0"
export let rel = "1"
export let deps = []
export let mkdeps_host = []
export let sources = [p"generated"]
export let checksums = ["SKIP"]
export let filetree = [
  {path: p"usr/share/configured-pkg/config.h", kind: "file"},
  {path: p"usr/share/configured-pkg/message.txt", kind: "file"},
]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  fs.install(p"config.h", fp"${dest}/usr/share/configured-pkg/config.h", 0o644, parents: true)?
  fs.install(p"message.txt", fp"${dest}/usr/share/configured-pkg/message.txt", 0o644, parents: true)?
}
""",
  )?

  fs.write(
    fp"${pkg}/proof.xsh",
    r"""error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  let header = fp"${root}/usr/share/configured-pkg/config.h"
  let message = fp"${root}/usr/share/configured-pkg/message.txt"

  if ! header.exists()? or ! message.exists()? {
    return Err(ProofError.Failed("proof-configured-pkg", "missing configured outputs"))
  }

  print "configured-pkg ok"
}

main(@args)?
""",
  )?

  let install_out = run.text xsh_bin() pm.xsh -- install $root $work $out $pkg ?
  test.contains(install_out, "configured-pkg configured-pkg-1.0.0-1 build: 2 files")?
  let header = fp"${root}/usr/share/configured-pkg/config.h".read_text()?
  test.contains(header, "#define ENABLE_CONFIGURED 1")?
  test.contains(header, "/* #undef DISABLED_FEATURE */")?
  let message = fp"${root}/usr/share/configured-pkg/message.txt".read_text()?
  test.contains(message, "name=configured-pkg")?
  test.contains(message, "mode=install")?
  test.contains(message, "literal=@UNKNOWN@")?
}

proc test_pm_package_build_extracts_tar_source(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let pkg = test.temp_dir(ctx, name: "tar-source-pkg")?
  let tar_root = test.temp_dir(ctx, name: "tar-root")?
  fs.mkdir(fp"${pkg}/files")?
  fs.mkdir(fp"${tar_root}/upstream-1.0")?

  fs.write(
    fp"${tar_root}/upstream-1.0/data.txt",
    """tar-source
""",
  )?

  archive.tar_create(fp"${pkg}/files/upstream.tar.gz", tar_root, [p"upstream-1.0"], compression: "gz")?

  fs.write(
    fp"${pkg}/PKGBUILD.xsh",
    r"""export let name = "tar-source-pkg"
export let ver = "1.0.0"
export let rel = "1"
export let deps = []
export let mkdeps_host = []
export let sources = [p"files/upstream.tar.gz"]
export let checksums = ["SKIP"]
export let filetree = [{path: p"usr/share/tar-source-pkg/data.txt", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  fs.install(p"data.txt", fp"${dest}/usr/share/tar-source-pkg/data.txt", 0o644, parents: true)?
}
""",
  )?

  fs.write(
    fp"${pkg}/proof.xsh",
    r"""error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  let payload = fp"${root}/usr/share/tar-source-pkg/data.txt"

  if ! payload.exists()? {
    return Err(ProofError.Failed("proof-tar-source-pkg", "missing extracted payload"))
  }

  print "tar-source-pkg ok"
}

main(@args)?
""",
  )?

  let install_out = run.text xsh_bin() pm.xsh -- install $root $work $out $pkg ?
  test.contains(install_out, "tar-source-pkg tar-source-pkg-1.0.0-1 build: 1 files")?

  test.eq(
    fp"${root}/usr/share/tar-source-pkg/data.txt".read_text()?,
    """tar-source
""",
  )?
}

proc test_pm_build_prepared_package_command_writes_manifest_and_tarball(ctx: TestContext) [fs, process, error] {
  let pkg = test.temp_dir(ctx, name: "prepared-pkg")?
  let src = test.temp_dir(ctx, name: "prepared-src")?
  let dest = test.temp_dir(ctx, name: "prepared-dest")?
  let out = test.temp_dir(ctx, name: "prepared-out")?
  let tarball = fp"${out}/prepared-pkg-1.0.0-1.tar.gz"

  fs.write(
    fp"${src}/payload.txt",
    """prepared
""",
  )?

  fs.write(
    fp"${pkg}/PKGBUILD.xsh",
    r"""export let name = "prepared-pkg"
export let ver = "1.0.0"
export let rel = "1"
export let deps = []
export let mkdeps_host = []
export let sources = []
export let checksums = []
export let filetree = [{path: p"usr/share/prepared-pkg/payload.txt", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  fs.install(p"payload.txt", fp"${dest}/usr/share/prepared-pkg/payload.txt", 0o644, parents: true)?
}
""",
  )?

  run.text xsh_bin() pm.xsh -- build-prepared-package $pkg $src $dest $tarball ?
  test.ok(tarball.exists()?)?

  test.eq(
    fp"${dest}/usr/share/prepared-pkg/payload.txt".read_text()?,
    """prepared
""",
  )?

  test.contains(
    fp"${dest}/var/lib/xsh-pm/packages/prepared-pkg/manifest.json".read_text()?,
    "usr/share/prepared-pkg/payload.txt",
  )?

  let tar_records = archive.tar_list(tarball)?
  let tar_entries = [entry.path.display() for entry in tar_records]
  test.contains(tar_entries.join("\n"), "usr/share/prepared-pkg/payload.txt")?
}

proc test_pm_missing_dependency(ctx: TestContext) [process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let status = run.status xsh_bin() pm.xsh -- install $root $work $out app_dir() 2> /dev/null
  test.eq(status.ok, false)?
}

proc test_pm_blocked_remove(ctx: TestContext) [process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  run.text xsh_bin() pm.xsh -- install $root $work $out dep_dir() app_dir() ?
  let status = run.status xsh_bin() pm.xsh -- remove $root $work $out dep 2> /dev/null
  test.eq(status.ok, false)?
}

proc test_pm_buildroot_missing_dependency_selection(ctx: TestContext) [fs, env, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let dep_pkg = pm_local.load_package_dirs([dep_dir()])?[0]
  let app_pkg = pm_local.load_package_dirs([app_dir()])?[0]
  let no_local: Map[Bool] = {}
  let dep_is_local = buildroot.local_package_names([dep_pkg, app_pkg])
  let missing_remote_dep = buildroot.missing_dependency_names(root, [app_pkg], false, no_local)?
  test.eq(missing_remote_dep.len(), 1)?
  test.eq(missing_remote_dep[0], "dep")?
  test.eq(buildroot.missing_dependency_names(root, [app_pkg], false, dep_is_local)?.len(), 0)?
  let missing_build_dep = buildroot.missing_dependency_names(root, [app_pkg], true, dep_is_local)?
  test.eq(missing_build_dep.len(), 1)?
  test.eq(missing_build_dep[0], "llvm-toolchain")?
  let db = fp"${root}/var/lib/xsh-pm/packages/dep"
  fs.mkdir(db)?

  json.write(
    fp"${db}/metadata.json",
    {
      name: "dep",
      ver: "1.0.0",
      rel: "1",
      deps: [],
      mkdeps_host: [],
      mkdeps_target: [],
      nostrip: false,
      extract_install: false,
      dir: "tests/xsh/fixtures/dep",
    },
  )?

  json.write(fp"${db}/manifest.json", ["usr/share/dep.txt"])?
  json.write(fp"${db}/etcsums.json", [])?
  test.eq(buildroot.missing_dependency_names(root, [app_pkg], false, no_local)?.len(), 0)?
}

proc test_pm_search(ctx: TestContext) [process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  run.text xsh_bin() pm.xsh -- install $root $work $out dep_dir() app_dir() ?
  let search_out = run.text xsh_bin() pm.xsh -- search $root $work $out app dep_dir() app_dir() ?
  test.contains(search_out, "app 1.0.0-1 local")?
  test.contains(search_out, "app 1.0.0-1 installed")?
}

proc test_pm_outdated_and_upgrade(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  run.text xsh_bin() pm.xsh -- install $root $work $out tool_v1_dir() ?

  test.eq(
    fp"${root}/usr/bin/tool".read_text()?,
    """v1
""",
  )?

  let outdated_out = run.text xsh_bin() pm.xsh -- outdated $root $work $out tool_v2_dir() ?
  test.contains(outdated_out, "tool 1.0.0-1 -> 1.1.0-1")?
  run.text xsh_bin() pm.xsh -- update $root $work $out tool_v2_dir() ?
  run.text xsh_bin() pm.xsh -- upgrade $root $work $out tool_v2_dir() ?

  test.eq(
    fp"${root}/usr/bin/tool".read_text()?,
    """v2
""",
  )?

  let info_out = run.text xsh_bin() pm.xsh -- info $root $work $out tool ?
  test.contains(info_out, "tool 1.1.0-1")?
}

proc test_pm_source_checksum(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let pkg = test.temp_dir(ctx, name: "pkg")?
  let _ = fs.copy_tree(source_pkg_dir(), pkg, parents: true, overwrite: true)?
  let pkgbuild_path = fp"${pkg}/PKGBUILD.xsh"

  fs.write(
    pkgbuild_path,
    pkgbuild_path.read_text()?.replace("export let checksums = [", "export let checksums: List[Str] = ["),
  )?

  let checksum_out = run.text xsh_bin() pm.xsh -- checksum $root $work $out $pkg ?
  test.contains(checksum_out, "source-pkg 6667b2d1aab6a00caa5aee5af8ad9f1465e567abf1c209d15727d57b3e8f6e5f")?
  let update_out = run.text xsh_bin() pm.xsh -- update-checksums $root $work $out $pkg ?
  test.contains(update_out, "source-pkg checksums updated")?

  test.eq(
    pkgbuild_path.read_text()?,
    r"""export let name = "source-pkg"

export let ver = "1.0.0"

export let rel = "1"

export let deps = []

export let mkdeps_host = []

export let sources = [p"files/data.txt"]

export let checksums = [
  "6667b2d1aab6a00caa5aee5af8ad9f1465e567abf1c209d15727d57b3e8f6e5f",
]

export let filetree = [{path: p"usr/share/source-pkg/data.txt", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/share/source-pkg/data.txt"
  fs.mkdir(target.parent)?
  fs.install(p"data.txt", target, 0o644)?
}
""",
  )?

  let shorthand_pkg = test.temp_dir(ctx, name: "shorthand-pkg")?
  let shorthand_copy = fs.copy_tree(source_pkg_dir(), shorthand_pkg, parents: true, overwrite: true)?
  test.ok(shorthand_copy.files > 0)?
  let shorthand_out = run.text xsh_bin() pm.xsh -- update-checksums $shorthand_pkg ?
  fs.remove(p".root", missing_ok: true)?
  fs.remove(p".work", missing_ok: true)?
  fs.remove(p".out", missing_ok: true)?
  test.contains(shorthand_out, "source-pkg checksums updated")?
  let shorthand_pkgbuild = fp"${shorthand_pkg}/PKGBUILD.xsh".read_text()?
  test.contains(shorthand_pkgbuild, "6667b2d1aab6a00caa5aee5af8ad9f1465e567abf1c209d15727d57b3e8f6e5f")?
  run.text xsh_bin() pm.xsh -- install $root $work $out $pkg ?

  test.eq(
    fp"${root}/usr/share/source-pkg/data.txt".read_text()?,
    """data
""",
  )?
}

proc test_pm_auth_and_file_repo(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let repo = test.temp_dir(ctx, name: "repo")?
  let install_root = test.temp_dir(ctx, name: "install-root")?
  let install_work = test.temp_dir(ctx, name: "install-work")?
  let install_out = test.temp_dir(ctx, name: "install-out")?
  let auth_out = run.text xsh_bin() pm.xsh -- auth $root $work $out my-secret-token ?
  test.contains(auth_out, "auth token stored")?
  run.text xsh_bin() pm.xsh -- install $root $work $out remote_app_dir() ?
  test.ok(fp"${out}/remote-app-1.0.0-1.tar.gz".exists()?)?
  let repo_url = f"file://${repo.display()}"
  let upload_out = run.text XSH_PM_REPO=$repo_url xsh_bin() pm.xsh -- upload $root $work $out remote_app_dir() ?
  test.contains(upload_out, "remote-app 1.0.0-1 uploaded")?
  let arch = fixture_arch()?
  test.ok(fp"${repo}/packages/${arch}/remote-app/remote-app-1.0.0-1.tar.gz".exists()?)?
  test.ok(fp"${repo}/metadata/${arch}/remote-app/remote-app-1.0.0-1.json".exists()?)?
  let repo_index_text = fp"${repo}/index.json".read_text()?
  test.contains(repo_index_text, "\"name\":\"remote-app\"")?
  let refresh_out = run.text XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- refresh-index $install_root $install_work $install_out ?
  test.contains(refresh_out, "remote-index 1 refreshed")?
  let remote_install_out = run.text XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- install $install_root $install_work $install_out remote-app ?
  test.contains(remote_install_out, "remote-app 1 remote-installed")?
  test.ok(fp"${install_out}/remote-cache/metadata/${arch}/remote-app/remote-app-1.0.0-1.json".exists()?)?
  test.eq(fp"${install_work}/remote-app-1.0.0-1-remote-install".exists()?, false)?

  test.eq(
    fp"${install_root}/usr/share/remote-app/payload.txt".read_text()?,
    """remote-app
""",
  )?
}

proc test_pm_build_set_stages_local_dependencies(ctx: TestContext) [fs, process, env, error] {
  let repo = test.temp_dir(ctx, name: "build-set-repo")?
  let pm_pkg = test.temp_dir(ctx, name: "build-set-laputa-pm")?
  let lib_pkg = test.temp_dir(ctx, name: "build-set-local-lib")?
  let app_pkg = test.temp_dir(ctx, name: "build-set-local-app")?
  let repo_url = f"file://${repo.display()}"
  let arch = fixture_arch()?

  fs.write(
    fp"${pm_pkg}/PKGBUILD.xsh",
    r"""export let name = "laputa-pm"
export let ver = "1.0.0"
export let rel = "1"
export let deps = []
export let mkdeps_host = []
export let sources = []
export let checksums = []
export let filetree = [{path: p"usr/share/laputa-pm/local.txt", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  fs.mkdir(fp"${dest}/usr/share/laputa-pm")?
  fs.write(fp"${dest}/usr/share/laputa-pm/local.txt", "local pm\n")?
}
""",
  )?

  fs.write(
    fp"${pm_pkg}/proof.xsh",
    r"""error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  if fp"${root}/usr/share/laputa-pm/local.txt".read_text()? != "local pm\n" {
    return Err(ProofError.Failed("laputa-pm", "missing local pm marker"))
  }

  print "laputa-pm ok"
}

main(@args)?
""",
  )?

  fs.write(
    fp"${lib_pkg}/PKGBUILD.xsh",
    r"""export let name = "local-lib"
export let ver = "1.0.0"
export let rel = "1"
export let deps = []
export let mkdeps_host = []
export let sources = []
export let checksums = []
export let filetree = [{path: p"usr/share/local-lib/payload.txt", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  fs.mkdir(fp"${dest}/usr/share/local-lib")?
  fs.write(fp"${dest}/usr/share/local-lib/payload.txt", "local-lib\n")?
}
""",
  )?

  fs.write(
    fp"${lib_pkg}/proof.xsh",
    r"""error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  if fp"${root}/usr/share/local-lib/payload.txt".read_text()? != "local-lib\n" {
    return Err(ProofError.Failed("local-lib", "missing payload"))
  }

  print "local-lib ok"
}

main(@args)?
""",
  )?

  fs.write(
    fp"${app_pkg}/PKGBUILD.xsh",
    r"""export let name = "local-app"
export let ver = "1.0.0"
export let rel = "1"
export let deps = ["local-lib"]
export let mkdeps_host = []
export let sources = []
export let checksums = []
export let filetree = [{path: p"usr/share/local-app/dep.txt", kind: "file"}]

export proc build(dest: Path) [fs, env, error] -> Result[Unit] {
  let root = fp"${env.get("LAPUTA_ROOT")?}"
  let payload = fp"${root}/usr/share/local-lib/payload.txt".read_text()?
  fs.mkdir(fp"${dest}/usr/share/local-app")?
  fs.write(fp"${dest}/usr/share/local-app/dep.txt", payload)?
}
""",
  )?

  fs.write(
    fp"${app_pkg}/proof.xsh",
    r"""error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  if fp"${root}/usr/share/local-app/dep.txt".read_text()? != "local-lib\n" {
    return Err(ProofError.Failed("local-app", "missing dependency payload"))
  }

  print "local-app ok"
}

main(@args)?
""",
  )?

  let output = run.text XSH_PM_BUILD_CHROOT=0 XSH_PM_REPO=$repo_url xsh_bin() pm.xsh -- build-set $repo $pm_pkg $lib_pkg $app_pkg ?
  test.contains(output, "laputa-pm proof: ok")?
  test.contains(output, "local-lib proof: ok")?
  test.contains(output, "local-app proof: ok")?
  test.contains(output, "size: ")?
  test.ok(fp"${repo}/packages/${arch}/laputa-pm/laputa-pm-1.0.0-1.tar.gz".exists()?)?
  test.ok(fp"${repo}/packages/${arch}/local-lib/local-lib-1.0.0-1.tar.gz".exists()?)?
  test.ok(fp"${repo}/packages/${arch}/local-app/local-app-1.0.0-1.tar.gz".exists()?)?
}

proc test_pm_remote_index_rejects_traversal_paths(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let repo = test.temp_dir(ctx, name: "repo")?
  let err = test.temp_path(ctx, name: "stderr")
  let arch = fixture_arch()?
  let repo_url = f"file://${repo.display()}"

  fs.write(
    fp"${repo}/index.json",
    f"""[{"arch":"${arch}","name":"evil","ver":"1.0.0","rel":"1","deps":[],"mkdeps_host":[],"mkdeps_target":[],"sha256":"","size":1,"tarball":"../escape.tar.gz","metadata":"metadata/${arch}/evil/evil-1.0.0-1.json","source_sha256":"","source_tarball":"","metapackage":false}]
""",
  )?

  let refresh_out = run.text XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- refresh-index $root $work $out ?
  test.contains(refresh_out, "remote-index 1 refreshed")?
  let status = run.status XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- install $root $work $out evil 2> $err
  test.eq(status.ok, false)?
  test.contains(err.read_text()?, "remote tarball must stay relative")?
  test.eq(fp"${out}/escape.tar.gz".exists()?, false)?
}

proc test_pm_remote_install_rejects_invalid_metadata_sidecar(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let repo = test.temp_dir(ctx, name: "repo")?
  let install_root = test.temp_dir(ctx, name: "install-root")?
  let install_work = test.temp_dir(ctx, name: "install-work")?
  let install_out = test.temp_dir(ctx, name: "install-out")?
  let err = test.temp_path(ctx, name: "pm.err")
  let repo_url = f"file://${repo.display()}"
  let arch = fixture_arch()?
  run.text xsh_bin() pm.xsh -- auth $root $work $out my-secret-token ?
  run.text xsh_bin() pm.xsh -- install $root $work $out remote_app_dir() ?
  run.text XSH_PM_REPO=$repo_url xsh_bin() pm.xsh -- upload $root $work $out remote_app_dir() ?

  json.write(
    fp"${repo}/metadata/${arch}/remote-app/remote-app-1.0.0-1.json",
    {
      arch,
      name: "other-app",
      ver: "1.0.0",
      rel: "1",
      manifest: ["usr/share/remote-app/payload.txt"],
      files: [],
      metadata_sha256: "corrupt",
    },
  )?

  let refresh_out = run.text XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- refresh-index $install_root $install_work $install_out ?
  test.contains(refresh_out, "remote-index 1 refreshed")?
  let status = run.status XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- install $install_root $install_work $install_out remote-app 2> $err
  test.eq(status.ok, false)?
  test.contains(err.read_text()?, "does not match remote-app 1.0.0-1")?
  test.eq(fp"${install_root}/usr/share/remote-app/payload.txt".exists()?, false)?
}

proc test_pm_remote_install_refetches_corrupt_cached_tarball(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let repo = test.temp_dir(ctx, name: "repo")?
  let install_root = test.temp_dir(ctx, name: "install-root")?
  let install_work = test.temp_dir(ctx, name: "install-work")?
  let install_out = test.temp_dir(ctx, name: "install-out")?
  let repo_url = f"file://${repo.display()}"
  let arch = fixture_arch()?
  let cached_tarball = fp"${install_out}/remote-cache/packages/${arch}/remote-app/remote-app-1.0.0-1.tar.gz"
  run.text xsh_bin() pm.xsh -- auth $root $work $out my-secret-token ?
  run.text xsh_bin() pm.xsh -- install $root $work $out remote_app_dir() ?
  run.text XSH_PM_REPO=$repo_url xsh_bin() pm.xsh -- upload $root $work $out remote_app_dir() ?
  run.text XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- refresh-index $install_root $install_work $install_out ?
  fs.mkdir(cached_tarball.parent)?
  fs.write(cached_tarball, "corrupt")?
  let install_out_text = run.text XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- install $install_root $install_work $install_out remote-app ?
  test.contains(install_out_text, "remote-app 1 remote-installed")?

  test.eq(
    fp"${install_root}/usr/share/remote-app/payload.txt".read_text()?,
    """remote-app
""",
  )?

  test.eq(
    hash.sha256(cached_tarball)?.hex(),
    hash.sha256(fp"${repo}/packages/${arch}/remote-app/remote-app-1.0.0-1.tar.gz")?.hex(),
  )?
}

proc test_pm_lifecycle_hooks(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let hook_log = test.temp_path(ctx, name: "hooks.log")
  let hook = test.temp_path(ctx, name: "pm-hook")

  fs.write(
    hook,
    r"""#!/bin/xsh --
proc main(...argv: List[Str]) [fs, env, error] {
  let _ = argv
  let log = fp"${env.get("HOOK_LOG")?}"
  var current = ""

  if log.exists()? {
    current = log.read_text()?
  }

  fs.write(log, f"${current}${env.get("XSH_PM_HOOK")?}|${env.get("XSH_PM_PACKAGE")?}|${env.get("XSH_PM_ACTION")?}\n")?
}

main(@args)?
""",
  )?

  hook.chmod(0o755)?
  run.text XSH_PM_HOOKS=$hook HOOK_LOG=$hook_log xsh_bin() pm.xsh -- install $root $work $out dep_dir() ?
  run.text XSH_PM_HOOKS=$hook HOOK_LOG=$hook_log xsh_bin() pm.xsh -- remove $root $work $out dep ?
  let log = hook_log.read_text()?
  test.contains(log, "pre-build|dep|install")?
  test.contains(log, "post-build|dep|install")?
  test.contains(log, "pre-install|dep|install")?
  test.contains(log, "post-install|dep|install")?
  test.contains(log, "pre-remove|dep|remove")?
  test.contains(log, "post-remove|dep|remove")?
}

proc test_pm_build_repo(ctx: TestContext) [fs, process, env, error] {
  let repo = test.temp_dir(ctx, name: "repo")?
  let output = run.text xsh_bin() pm.xsh -- build $repo baseinit_dir() ?
  test.contains(output, "baseinit")?
  test.contains(output, "stage: done")?
  test.ok(fp"${repo}/index.json".exists()?)?
  let arch = fixture_arch()?
  test.ok(fp"${repo}/packages/${arch}/baseinit/baseinit-2.0.0-1.tar.gz".exists()?)?
}

proc test_pm_upload_repo_export_includes_source_mirror(ctx: TestContext) [fs, process, env, error] {
  let repo = test.temp_dir(ctx, name: "repo")?
  let remote = test.temp_dir(ctx, name: "remote")?
  let repo_url = f"file://${remote.display()}"
  let arch = fixture_arch()?
  let build_out = run.text xsh_bin() pm.xsh -- build $repo remote_app_dir() ?
  test.contains(build_out, "remote-app 1.0.0-1 stage: done")?
  test.ok(fp"${repo}/.out/source-mirrors/remote-app-1.0.0-1-${arch}.tar.gz".exists()?)?
  let export_out = run.text XSH_PM_REPO=$repo_url LAPUTA_TOKEN=token xsh_bin() pm.xsh -- upload-repo-export $repo ?
  test.contains(export_out, "repo-export loading remote index")?
  test.contains(export_out, "repo-export aarch64 remote-app 1.0.0-1 uploading")?
  test.contains(export_out, "repo-export aarch64 remote-app uploading tarball")?
  test.contains(export_out, f"${arch} remote-app 1.0.0-1 exported")?
  test.contains(export_out, "repo export uploaded")?
  let source_rel = fp"sources/remote-app/remote-app-1.0.0-1-${arch}-src.tar.gz"
  var remote_rows: List[Record] = json.read(fp"${remote}/index.json")?
  var legacy_rows = [{...row, mkdeps_target: []} for row in remote_rows]
  json.write(fp"${remote}/index.json", legacy_rows)?
  let repeat_out = run.text XSH_PM_REPO=$repo_url LAPUTA_TOKEN=token xsh_bin() pm.xsh -- upload-repo-export $repo ?
  test.contains(repeat_out, f"repo-export ${arch} remote-app 1.0.0-1 already-exported")?
  test.ok(! ("uploading" in repeat_out))?
  test.ok(fp"${remote}/${source_rel}".exists()?)?
  let index_text = fp"${remote}/index.json".read_text()?
  test.contains(index_text, f"\"source_tarball\":\"${source_rel.display()}\"")?
  test.contains(index_text, "\"source_sha256\":\"")?
  let err = test.temp_path(ctx, name: "export-missing.err")
  fs.remove(fp"${repo}/.out/source-mirrors/remote-app-1.0.0-1-${arch}.tar.gz")?
  fs.remove(fp"${repo}/packages/${arch}/remote-app/remote-app-1.0.0-1.tar.gz")?
  let missing_status = run.status XSH_PM_REPO=$repo_url LAPUTA_TOKEN=token xsh_bin() pm.xsh -- upload-repo-export $repo 2> $err
  test.eq(missing_status.ok, false)?
  test.contains(err.read_text()?, "remote-app-1.0.0-1.tar.gz is missing")?
}

proc test_pm_build_repo_requires_package_dirs(ctx: TestContext) [fs, process, error] {
  let repo = test.temp_dir(ctx, name: "repo")?
  let err = test.temp_path(ctx, name: "pm.err")
  let status = run.status xsh_bin() pm.xsh -- build $repo 2> $err
  test.eq(status.ok, false)?
  test.contains(err.read_text()?, "usage: pm build REPO_DIR PKGDIR...")?
}

proc test_pm_help(ctx: TestContext) [process, error] {
  let _ = ctx
  let help = run.text xsh_bin() pm.xsh -- "-h" ?
  test.contains(help, "usage: pm COMMAND [ARG...]")?
  test.contains(help, "world-plan PKGDIR... [--arch ARCH] [--build] [--upload] [--to-tranche N] [-j N|--jobs N]")?
  let world_help = run.text xsh_bin() pm.xsh -- world-plan "--help" ?
  test.contains(world_help, "usage: pm world-plan ...PKGDIR [OPTIONS]")?
  test.contains(world_help, "--arch ARCH")?
  test.contains(world_help, "--to-tranche N")?
}

proc test_pm_world_musl_elf_dependency_audit_detects_elf_metadata(ctx: TestContext) [error] {
  let _ = ctx
  test.ok(pm_elfdeps.elf_info_mentions_musl(["libc.so"], ""))?
  test.ok(pm_elfdeps.elf_info_mentions_musl([], "/lib/ld-musl-aarch64.so.1"))?
  test.eq(pm_elfdeps.elf_info_mentions_musl(["libz.so.1"], ""), false)?
}

proc test_pm_world_elf_dependency_audit_detects_missing_provider_deps(ctx: TestContext) [error] {
  let _ = ctx
  var providers: Map[Str] = {}
  providers["libz.so.1"] = "zlib"
  providers["libssl.so.3"] = "openssl"

  let missing = pm_elfdeps.missing_elf_runtime_dependencies(
    "app",
    ["zlib"],
    ["libz.so.1", "libssl.so.3"],
    "",
    providers,
  )

  test.eq(missing.len(), 1)?
  test.eq(missing[0].soname, "libssl.so.3")?
  test.eq(missing[0].provider, "openssl")?
  test.eq(pm_elfdeps.missing_elf_runtime_dependencies("zlib", [], ["libz.so.1"], "", providers).len(), 0)?

  test.eq(
    pm_elfdeps.missing_elf_runtime_dependencies("app", ["zlib", "openssl"], ["libz.so.1", "libssl.so.3"], "", providers).len(),
    0,
  )?
}

proc test_pm_world_elf_dependency_audit_resolves_runtime_closure(ctx: TestContext) [error] {
  let _ = ctx
  var package_deps: Map[List[Str]] = {}
  package_deps["libseat"] = ["seatd"]
  package_deps["seatd"] = ["musl"]
  let closure = pm_elfdeps.runtime_dependency_closure(["libseat"], package_deps)
  test.ok(closure.get("libseat", false))?
  test.ok(closure.get("seatd", false))?
  test.ok(closure.get("musl", false))?
}

proc test_pm_world_elf_dependency_audit_ignores_library_symlink_providers(ctx: TestContext) [fs, error] {
  let root = test.temp_dir(ctx, name: "elf-provider-root")?
  let pixman_db = fp"${root}/var/lib/xsh-pm/packages/pixman"
  let pixman_dev_db = fp"${root}/var/lib/xsh-pm/packages/pixman-dev"
  fs.mkdir(pixman_db)?
  fs.mkdir(pixman_dev_db)?
  fs.mkdir(fp"${root}/usr/lib")?
  fs.write(fp"${root}/usr/lib/libpixman-1.so.0", "regular library")?
  fs.symlink(p"libpixman-1.so.0", fp"${root}/usr/lib/libpixman-1.so")?
  json.write(fp"${pixman_db}/manifest.json", ["usr/lib/libpixman-1.so.0"])?
  json.write(fp"${pixman_dev_db}/manifest.json", ["usr/lib/libpixman-1.so"])?
  let providers = pm_elfdeps.collect_library_providers(root)?
  test.eq(providers.get("libpixman-1.so.0", ""), "pixman")?
}

proc test_pm_requires_package_proof(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let pkg = test.temp_dir(ctx, name: "proofless")?
  let err = test.temp_path(ctx, name: "pm.err")

  fs.write(
    fp"${pkg}/PKGBUILD.xsh",
    r"""export let name = "proofless"
export let ver = "1.0.0"
export let rel = "1"
export let deps = []
export let mkdeps_host = []
export let sources = []
export let checksums = []
export let filetree = [{path: p"proofless.txt", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  fs.write(fp"${dest}/proofless.txt", "proofless\n")?
}
""",
  )?

  let status = run.status xsh_bin() pm.xsh -- install $root $work $out $pkg 2> $err
  test.eq(status.ok, false)?
  test.contains(err.read_text()?, "proofless is missing proof.xsh")?
}

proc test_pm_requires_service_definition(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let pkg = test.temp_dir(ctx, name: "svcless")?
  let err = test.temp_path(ctx, name: "pm.err")

  fs.write(
    fp"${pkg}/PKGBUILD.xsh",
    r"""export let name = "svcless"
export let ver = "1.0.0"
export let rel = "1"
export let deps = []
export let mkdeps_host = []
export let sources = []
export let checksums = []
export let filetree = [{path: p"usr/lib/xinit/services/svcless.xsh", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  fs.mkdir(fp"${dest}/usr/lib/xinit/services")?
  fs.write(fp"${dest}/usr/lib/xinit/services/svcless.xsh", "export let service = {}\n")?
}
""",
  )?

  fs.write(
    fp"${pkg}/proof.xsh",
    """proc main(root: Path = /rootfs) [fs, error] {
  let _ = root
  print "svcless ok"
}

main(@args)?
""",
  )?

  let status = run.status xsh_bin() pm.xsh -- install $root $work $out $pkg 2> $err
  test.eq(status.ok, false)?

  test.contains(
    err.read_text()?,
    "svcless installs an xinit service under /usr/lib/xinit/services/ but is missing service.xsh",
  )?
}

proc test_pm_world_plan_build_and_upload(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let remote = test.temp_dir(ctx, name: "world-remote")?
  let repo_url = f"file://${remote.display()}"
  let output = run.text HOME=$home NO_COLOR=1 XSH_PM_BUILD_CHROOT=0 XSH_PM_REPO=$repo_url LAPUTA_TOKEN=token xsh_bin() pm.xsh -- world-plan world_pm_dir() world_lib_dir() world_app_dir() --build --upload --jobs 2 ?
  test.contains(output, "world-plan")?
  test.contains(output, f"world-repo ${home.display()}/.cache/laputa/world-")?
  test.contains(output, "jobs 2")?
  test.contains(output, "tranche 0")?
  test.contains(output, "tranche 1")?
  test.ok(! ("`--" in output))?
  test.ok(! ("after " in output))?
  test.contains(output, "world-lib proof: ok")?
  test.contains(output, "world-app proof: ok")?
  test.contains(output, "world-plan build complete")?
  test.contains(output, "size: ")?
  test.contains(output, "repo export uploaded")?
  let stage = single_world_cache(home)?
  let arch = fixture_arch()?
  test.ok(fp"${stage}/.world/state.json".exists()?)?
  test.ok(fp"${stage}/packages/${arch}/world-lib/world-lib-1.0.0-1.tar.gz".exists()?)?
  test.ok(fp"${stage}/metadata/${arch}/world-lib/world-lib-1.0.0-1.json".exists()?)?
  test.ok(fp"${remote}/packages/${arch}/world-app/world-app-1.0.0-1.tar.gz".exists()?)?
  test.ok(fp"${remote}/metadata/${arch}/world-app/world-app-1.0.0-1.json".exists()?)?
  let state = fp"${stage}/.world/state.json".read_text()?
  test.contains(state, "\"complete\":true")?
  test.contains(state, "\"proofed\"")?
  let rerun = run.text HOME=$home NO_COLOR=1 XSH_PM_BUILD_CHROOT=0 XSH_PM_REPO=$repo_url LAPUTA_TOKEN=token xsh_bin() pm.xsh -- world-plan world_pm_dir() world_lib_dir() world_app_dir() --build --jobs 2 ?
  test.contains(rerun, "laputa-pm 1.0.0-1 stage: cached")?
  test.ok(! ("laputa-pm 1.0.0-1 ->" in rerun))?
}

proc test_pm_world_plan_build_to_tranche_and_resume(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let first = run.text HOME=$home NO_COLOR=1 XSH_PM_BUILD_CHROOT=0 XSH_PM_OFFLINE=1 xsh_bin() pm.xsh -- world-plan world_pm_dir() world_lib_dir() world_app_dir() --build --to-tranche 1 --jobs 1 ?
  test.contains(first, "world-plan build paused at tranche 1")?
  let stage = single_world_cache(home)?
  let arch = fixture_arch()?
  test.ok(fp"${stage}/packages/${arch}/world-lib/world-lib-1.0.0-1.tar.gz".exists()?)?
  test.ok(! fp"${stage}/packages/${arch}/world-app/world-app-1.0.0-1.tar.gz".exists()?)?
  test.contains(fp"${stage}/.world/state.json".read_text()?, "\"complete\":false")?
  let second = run.text HOME=$home NO_COLOR=1 XSH_PM_BUILD_CHROOT=0 XSH_PM_OFFLINE=1 xsh_bin() pm.xsh -- world-plan world_pm_dir() world_lib_dir() world_app_dir() --build --jobs 1 ?
  test.contains(second, "world-app 1.0.0-1 stage: done")?
  test.contains(second, "world-plan build complete")?
  test.ok(fp"${stage}/packages/${arch}/world-app/world-app-1.0.0-1.tar.gz".exists()?)?
  test.contains(fp"${stage}/.world/state.json".read_text()?, "\"complete\":true")?
}

proc test_pm_world_plan_stable_cache_invalidates_on_pkgbuild_edit(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let pkg = test.temp_dir(ctx, name: "world-pm-copy")?
  let _ = fs.copy_tree(world_pm_dir(), pkg, parents: true, overwrite: true)?
  run.text HOME=$home XSH_PM_BUILD_CHROOT=0 XSH_PM_OFFLINE=1 xsh_bin() pm.xsh -- world-plan $pkg --build --to-tranche 0 --jobs 1 ?
  let stage = single_world_cache(home)?

  fs.write(
    fp"${pkg}/PKGBUILD.xsh",
    f"""${fp"${pkg}/PKGBUILD.xsh".read_text()?}
# invalidate world
""",
  )?

  let status = run.status HOME=$home XSH_PM_BUILD_CHROOT=0 XSH_PM_OFFLINE=1 xsh_bin() pm.xsh -- world-plan $pkg --build --jobs 1
  test.eq(status.ok, true)?
  test.eq(single_world_cache(home)?.display(), stage.display())?
  test.contains(fp"${stage}/.world/state.json".read_text()?, "\"complete\":true")?
}

proc test_pm_world_plan_parallel_package_setup_error_goes_to_build_log(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let err = test.temp_path(ctx, name: "pm.err")
  let pkg = test.temp_dir(ctx, name: "bad-source-world-pkg")?
  let _ = fs.copy_tree(source_pkg_dir(), pkg, parents: true, overwrite: true)?
  fs.write(fp"${pkg}/PKGBUILD.xsh", fp"${pkg}/PKGBUILD.xsh".read_text()?.replace("source-pkg", "laputa-pm"))?
  let status = run.status HOME=$home XSH_PM_BUILD_CHROOT=0 XSH_PM_OFFLINE=1 xsh_bin() pm.xsh -- world-plan $pkg --build --jobs 2 2> $err
  test.eq(status.ok, false)?
  let stderr = err.read_text()?
  test.ok(! ("par-map error" in stderr))?
  test.contains(stderr, "tranche 0: 1/1 failed")?
  let stage = single_world_cache(home)?
  let arch = fixture_arch()?
  let log = fp"${stage}/packages/${arch}/laputa-pm/build.log".read_text()?
  test.contains(log, "world-build error: sha256 digest mismatch")?
}

proc test_pm_world_plan_upload_requires_complete_stage(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let remote = test.temp_dir(ctx, name: "world-remote")?
  let err = test.temp_path(ctx, name: "pm.err")
  let repo_url = f"file://${remote.display()}"
  let status = run.status HOME=$home XSH_PM_REPO=$repo_url LAPUTA_TOKEN=token xsh_bin() pm.xsh -- world-plan world_pm_dir() world_lib_dir() world_app_dir() --upload 2> $err
  test.eq(status.ok, false)?
  test.contains(err.read_text()?, "run world-plan --build first")?
}

proc test_pm_world_plan_annotates_remote_not_newer(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let repo = test.temp_dir(ctx, name: "repo")?
  let repo_url = f"file://${repo.display()}"
  run.text xsh_bin() pm.xsh -- build $repo world_pm_dir() ?
  let output = run.text HOME=$home NO_COLOR=1 XSH_PM_REPO=$repo_url xsh_bin() pm.xsh -- world-plan world_pm_dir() ?
  test.contains(output, "laputa-pm 1.0.0-1")?
  test.ok(! ("remote same" in output))?
  test.ok(! ("remote newer" in output))?
  test.ok(! ("->" in output))?
}

proc test_pm_world_plan_displays_remote_to_local_catchup(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let repo = test.temp_dir(ctx, name: "repo")?
  let repo_url = f"file://${repo.display()}"
  let arch = fixture_arch()?
  let no_deps = []
  let no_mkdeps_host = []

  json.write(
    fp"${repo}/index.json",
    [
      {
        arch,
        name: "laputa-pm",
        ver: "1.0.0",
        rel: "0",
        deps: no_deps,
        mkdeps_host: no_mkdeps_host,
        sha256: "",
        size: 0,
        tarball: f"packages/${arch}/laputa-pm/laputa-pm-1.0.0-0.tar.gz",
        metadata: "",
        source_sha256: "",
        source_tarball: "",
        metapackage: false,
      },
    ],
  )?

  let output = run.text HOME=$home NO_COLOR=1 XSH_PM_REPO=$repo_url xsh_bin() pm.xsh -- world-plan world_pm_dir() ?
  test.contains(output, "laputa-pm 1.0.0-0 -> 1.0.0-1 because local rel above remote")?
  test.ok(! ("remote newer" in output))?
}

proc test_pm_world_plan_arch_option(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let output = run.text HOME=$home NO_COLOR=1 XSH_PM_OFFLINE=1 xsh_bin() pm.xsh -- world-plan world_pm_dir() --arch amd64 ?
  test.contains(output, "world-plan x86_64 1 package")?
}

proc test_pm_world_plan_displays_dependency_rel_bumps(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let repo = test.temp_dir(ctx, name: "repo")?
  let repo_url = f"file://${repo.display()}"
  let arch = fixture_arch()?
  run.text xsh_bin() pm.xsh -- build $repo world_pm_dir() world_lib_dir() world_app_dir() ?
  let no_deps = []
  let no_mkdeps_host = []
  let lib_deps = ["laputa-pm"]
  let app_deps = ["world-lib"]

  json.write(
    fp"${repo}/index.json",
    [
      {
        arch,
        name: "laputa-pm",
        ver: "1.0.0",
        rel: "0",
        deps: no_deps,
        mkdeps_host: no_mkdeps_host,
        sha256: "",
        size: 0,
        tarball: f"packages/${arch}/laputa-pm/laputa-pm-1.0.0-0.tar.gz",
        metadata: "",
        source_sha256: "",
        source_tarball: "",
        metapackage: false,
      },
      {
        arch,
        name: "world-lib",
        ver: "1.0.0",
        rel: "1",
        deps: lib_deps,
        mkdeps_host: no_mkdeps_host,
        sha256: "",
        size: 0,
        tarball: f"packages/${arch}/world-lib/world-lib-1.0.0-1.tar.gz",
        metadata: "",
        source_sha256: "",
        source_tarball: "",
        metapackage: false,
      },
      {
        arch,
        name: "world-app",
        ver: "1.0.0",
        rel: "1",
        deps: app_deps,
        mkdeps_host: no_mkdeps_host,
        sha256: "",
        size: 0,
        tarball: f"packages/${arch}/world-app/world-app-1.0.0-1.tar.gz",
        metadata: "",
        source_sha256: "",
        source_tarball: "",
        metapackage: false,
      },
    ],
  )?

  let err = test.temp_path(ctx, name: "world-dependency-rel.err")
  let status = run.status HOME=$home NO_COLOR=1 XSH_PM_BUILD_CHROOT=0 XSH_PM_REPO=$repo_url xsh_bin() pm.xsh -- world-plan world_pm_dir() world_lib_dir() world_app_dir() --build --jobs 1 2> $err
  test.eq(status.ok, false)?
  test.contains(err.read_text()?, "world-lib dependencies changed")?
  test.contains(err.read_text()?, "bump its declared rel above 1.0.0-1")?
}

proc test_pm_world_plan_rejects_declared_rel_behind_remote(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let remote = test.temp_dir(ctx, name: "world-remote")?
  let repo_url = f"file://${remote.display()}"
  let arch = fixture_arch()?
  let no_deps = []
  let no_mkdeps_host = []
  let metadata_rel = fp"metadata/${arch}/laputa-pm/laputa-pm-1.0.0-2.json"
  fs.mkdir(fp"${remote}/${metadata_rel}".parent)?
  json.write(fp"${remote}/${metadata_rel}", {metadata_sha256: "remote-old"})?

  json.write(
    fp"${remote}/index.json",
    [
      {
        arch,
        name: "laputa-pm",
        ver: "1.0.0",
        rel: "2",
        deps: no_deps,
        mkdeps_host: no_mkdeps_host,
        sha256: "",
        size: 0,
        tarball: f"packages/${arch}/laputa-pm/laputa-pm-1.0.0-2.tar.gz",
        metadata: metadata_rel.display(),
        source_sha256: "",
        source_tarball: "",
        metapackage: false,
      },
    ],
  )?

  let err = test.temp_path(ctx, name: "declared-rel.err")
  let status = run.status HOME=$home XSH_PM_BUILD_CHROOT=0 XSH_PM_REPO=$repo_url xsh_bin() pm.xsh -- world-plan world_pm_dir() --build --jobs 1 2> $err
  test.eq(status.ok, false)?
  test.contains(err.read_text()?, "laputa-pm declares 1.0.0-1 but 1.0.0-2 is already published")?
}

proc test_pm_world_plan_upload_verifies_staged_artifacts(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let remote = test.temp_dir(ctx, name: "world-remote")?
  let err = test.temp_path(ctx, name: "pm.err")
  let repo_url = f"file://${remote.display()}"
  run.text HOME=$home XSH_PM_BUILD_CHROOT=0 XSH_PM_OFFLINE=1 xsh_bin() pm.xsh -- world-plan world_pm_dir() world_lib_dir() world_app_dir() --build ?
  let stage = single_world_cache(home)?
  let arch = fixture_arch()?
  fs.write(fp"${stage}/packages/${arch}/world-app/world-app-1.0.0-1.tar.gz", "corrupt")?
  let status = run.status HOME=$home XSH_PM_REPO=$repo_url LAPUTA_TOKEN=token xsh_bin() pm.xsh -- world-plan world_pm_dir() world_lib_dir() world_app_dir() --upload 2> $err
  test.eq(status.ok, false)?
  test.contains(err.read_text()?, "size mismatch")?
}

proc test_pm_unknown_command_without_extension_fails(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let path_dir = test.temp_dir(ctx, name: "path")?
  let err = test.temp_path(ctx, name: "pm.err")
  let path_text = f"${path_dir.display()}:${env.get("PATH")?}"
  let status = run.status PATH=$path_text xsh_bin() pm.xsh -- missing-action $root $work $out 2> $err
  let stderr = err.read_text()?
  test.eq(status.ok, false)?
  test.contains(stderr, "usage: pm ACTION ROOT WORK OUT [ARGS...]")?
  test.contains(stderr, "unknown command missing-action")?
}

proc test_pm_search_requires_query(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let err = test.temp_path(ctx, name: "pm.err")
  let status = run.status xsh_bin() pm.xsh -- search $root $work $out 2> $err
  test.eq(status.ok, false)?
  test.contains(err.read_text()?, "usage: pm search ROOT WORK OUT QUERY [PKGDIR...]")?
}

proc test_pm_extension_help_discovers_executables_in_path_order(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let first = test.temp_dir(ctx, name: "first")?
  let second = test.temp_dir(ctx, name: "second")?
  let ignored = fp"${first}/pm-ignored"
  let shadow_first = fp"${first}/pm-shadow"
  let shadow_second = fp"${second}/pm-shadow"
  let plain = fp"${second}/pm-plain"

  fs.write(
    ignored,
    """#!/bin/xsh --
# ignored summary
""",
  )?

  fs.write(
    shadow_first,
    """#!/bin/xsh --
# first summary
""",
  )?

  fs.write(
    shadow_second,
    """#!/bin/xsh --
# second summary
""",
  )?

  fs.write(
    plain,
    """#!/bin/xsh --
not a comment summary
""",
  )?

  shadow_first.chmod(0o755)?
  shadow_second.chmod(0o755)?
  plain.chmod(0o755)?
  let path_text = f"${first.display()}:${second.display()}:${env.get("PATH")?}"
  let help = run.text PATH=$path_text xsh_bin() pm.xsh -- help-ext $root $work $out ?
  test.contains(help, "extension shadow first summary")?
  test.eq("ignored" in help, false)?
  test.eq("second summary" in help, false)?
  test.eq("not a comment summary" in help, false)?
}

proc test_pm_extension_invocation_environment(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let path_dir = test.temp_dir(ctx, name: "path")?
  let log = test.temp_path(ctx, name: "extension.log")
  let extension = fp"${path_dir}/pm-inspect"

  fs.write(
    extension,
    r"""#!/bin/xsh --
proc main(...argv: List[Str]) [fs, env, error] {
  let _ = argv
  fs.write(
    fp"${env.get("EXT_LOG")?}",
    f"root=${env.get("XSH_PM_ROOT")?}\nwork=${env.get("XSH_PM_WORK")?}\nout=${env.get("XSH_PM_OUT")?}\naction=${env.get("XSH_PM_ACTION")?}\nargs=<${env.get("XSH_PM_ARGS")?}>\n",
  )?
}

main(@args)?
""",
  )?

  extension.chmod(0o755)?
  let path_text = f"${path_dir.display()}:${env.get("PATH")?}"
  run.text PATH=$path_text EXT_LOG=$log xsh_bin() pm.xsh -- inspect $root $work $out one two ?
  let env_log = log.read_text()?
  test.contains(env_log, f"root=${root.display()}")?
  test.contains(env_log, f"work=${work.display()}")?
  test.contains(env_log, f"out=${out.display()}")?
  test.contains(env_log, "action=inspect")?

  test.contains(
    env_log,
    """args=<one
two>""",
  )?
}

proc test_pm_remote_metapackage_installs_dependencies(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let repo = test.temp_dir(ctx, name: "repo")?
  let install_root = test.temp_dir(ctx, name: "install-root")?
  let install_work = test.temp_dir(ctx, name: "install-work")?
  let install_out = test.temp_dir(ctx, name: "install-out")?
  let repo_url = f"file://${repo.display()}"
  run.text xsh_bin() pm.xsh -- auth $root $work $out my-secret-token ?
  run.text xsh_bin() pm.xsh -- install $root $work $out remote_app_dir() ?
  run.text XSH_PM_REPO=$repo_url xsh_bin() pm.xsh -- upload $root $work $out remote_app_dir() ?
  let upload_meta = run.text XSH_PM_REPO=$repo_url xsh_bin() pm.xsh -- upload $root $work $out remote_meta_dir() ?
  test.contains(upload_meta, "remote-meta 1.0.0-1 staged")?
  let repo_index_text = fp"${repo}/index.json".read_text()?
  test.contains(repo_index_text, "\"name\":\"remote-meta\"")?
  test.contains(repo_index_text, "\"metapackage\":true")?
  let refresh_out = run.text XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- refresh-index $install_root $install_work $install_out ?
  test.contains(refresh_out, "remote-index 2 refreshed")?
  let install_out_text = run.text XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- install $install_root $install_work $install_out remote-meta ?
  test.contains(install_out_text, "remote-app 1 remote-installed")?
  test.contains(install_out_text, "remote-meta 1.0.0-1 registered")?
  test.ok(fp"${install_root}/var/lib/xsh-pm/packages/remote-meta/metadata.json".exists()?)?

  test.eq(
    fp"${install_root}/usr/share/remote-app/payload.txt".read_text()?,
    """remote-app
""",
  )?
}

proc test_pm_refresh_empty_file_repo_writes_empty_cache(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let repo = test.temp_dir(ctx, name: "repo")?
  let repo_url = f"file://${repo.display()}"
  let refresh_out = run.text XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- refresh-index $root $work $out ?
  test.contains(refresh_out, "remote-index 0 refreshed")?
  test.eq(fp"${out}/remote-index.json".read_text()?.trim(), "[]")?
}

proc test_pm_refresh_index_merges_primary_over_public(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let primary = test.temp_dir(ctx, name: "primary-repo")?
  let public = test.temp_dir(ctx, name: "public-repo")?
  let arch = fixture_arch()?
  let primary_url = f"file://${primary.display()}"
  let public_url = f"file://${public.display()}"

  json.write(
    fp"${public}/index.json",
    [
      {
        arch,
        name: "laputa-pm",
        ver: "1.0.0",
        rel: "1",
        deps: [],
        mkdeps_host: [],
        mkdeps_target: [],
        sha256: "public",
        size: 1,
        tarball: "packages/public/laputa-pm.tar.gz",
        metadata: "metadata/public/laputa-pm.json",
        source_sha256: "",
        source_tarball: "",
        metapackage: false,
      },
      {
        arch,
        name: "public-only",
        ver: "1.0.0",
        rel: "1",
        deps: [],
        mkdeps_host: [],
        mkdeps_target: [],
        sha256: "public-only",
        size: 1,
        tarball: "packages/public/public-only.tar.gz",
        metadata: "metadata/public/public-only.json",
        source_sha256: "",
        source_tarball: "",
        metapackage: false,
      },
    ],
  )?

  json.write(
    fp"${primary}/index.json",
    [
      {
        arch,
        name: "laputa-pm",
        ver: "1.0.0",
        rel: "2",
        deps: [],
        mkdeps_host: [],
        mkdeps_target: [],
        sha256: "primary",
        size: 2,
        tarball: "packages/primary/laputa-pm.tar.gz",
        metadata: "metadata/primary/laputa-pm.json",
        source_sha256: "",
        source_tarball: "",
        metapackage: false,
      },
    ],
  )?

  let refresh_out = run.text XSH_PM_REPO=$primary_url XSH_PM_PUBLIC_REPO=$public_url xsh_bin() pm.xsh -- refresh-index $root $work $out ?
  test.contains(refresh_out, "remote-index 2 refreshed")?
  let cached = fp"${out}/remote-index.json".read_text()?
  test.contains(cached, "\"name\":\"laputa-pm\"")?
  test.contains(cached, "\"rel\":\"2\"")?
  test.contains(cached, "\"sha256\":\"primary\"")?
  test.contains(cached, "\"name\":\"public-only\"")?
}

proc test_make_runner_behaviors(ctx: TestContext) [fs, process, env, time, error] {
  let helper = test.temp_path(ctx, name: "make-task-helper.xsh")

  let compiled = make.compile_c_tasks(
    /bin/cc,
    "aarch64-linux-musl",
    ["-O2"],
    ["-DTEST"],
    ["-Isrc"],
    p"srcroot",
    [p"src/utils/config.c", p"wpa_supplicant/config.c"],
    p"obj",
  )

  test.eq(compiled.objects[0].display(), "obj/src_utils_config.o")?
  test.eq(compiled.objects[1].display(), "obj/wpa_supplicant_config.o")?
  test.eq(compiled.tasks[0].inputs[0].display(), "srcroot/src/utils/config.c")?
  test.eq(compiled.deps, [compiled.tasks[0].name, compiled.tasks[1].name])?
  test.eq(make.task_deps(compiled.tasks, [compiled.objects[1]]), [compiled.tasks[1].name])?

  let program = make.c_program({
    cc: /bin/cc,
    triple: "aarch64-linux-musl",
    cflags: ["-O2"],
    defs: [],
    includes: [],
    root: p".",
    sources: [p"main.c", p"util.c"],
    out_dir: p"obj",
    out: p"obj/tool",
    libs: [],
    ldflags: ["-static"],
    deps: [],
  })

  test.eq(program.output.display(), "obj/tool")?
  test.eq(program.tasks.len(), 3)?
  test.eq(program.deps[2], "obj/tool")?
  test.eq(program.tasks[2].deps, [program.tasks[0].name, program.tasks[1].name])?

  let multi = make.c_multi_program({
    cc: /bin/cc,
    triple: "aarch64-linux-musl",
    cflags: ["-O2"],
    defs: [],
    includes: [],
    root: p"src",
    out_dir: p"obj",
    groups: [
      {
        name: "shared",
        cflags: [],
        defs: [],
        includes: [],
        root: p"",
        sources: [p"common.c", p"util.c"],
        out_dir: p"",
        deps: [],
      },
      {
        name: "feature",
        cflags: ["-fPIC"],
        defs: ["-DFEATURE"],
        includes: [],
        root: p"",
        sources: [p"feature.cxx"],
        out_dir: p"",
        deps: [],
      },
    ],
    targets: [
      {
        name: "tool-a",
        groups: ["shared"],
        sources: [p"main-a.c"],
        libs: [],
        ldflags: ["-static"],
        out: p"bin/tool-a",
        deps: [],
      },
      {
        name: "tool-b",
        groups: ["shared", "feature"],
        sources: [p"main-b.c"],
        libs: [],
        ldflags: [],
        out: p"bin/tool-b",
        deps: [],
      },
    ],
  })?

  test.eq(multi.outputs.get("tool-a")?.display(), "bin/tool-a")?
  test.eq(multi.outputs.get("tool-b")?.display(), "bin/tool-b")?
  test.eq(multi.tasks.len(), 7)?
  test.eq(multi.tasks[0].outputs[0].display(), "obj/shared/common.o")?
  test.eq(multi.tasks[2].argv[0], "c++")?
  test.eq("-DFEATURE" in multi.tasks[2].argv, true)?
  test.eq(multi.tasks[3].outputs[0].display(), "obj/tool-a/main-a.o")?
  test.eq(multi.tasks[4].deps, [multi.tasks[0].name, multi.tasks[1].name, multi.tasks[3].name])?
  test.eq(multi.tasks[6].argv[0], "c++")?
  test.eq(multi.tasks[6].deps, [multi.tasks[0].name, multi.tasks[1].name, multi.tasks[2].name, multi.tasks[5].name])?

  match make.c_multi_program({
    cc: /bin/cc,
    triple: "aarch64-linux-musl",
    cflags: [],
    defs: [],
    includes: [],
    root: p".",
    out_dir: p"obj",
    groups: [],
    targets: [
      {
        name: "bad",
        groups: ["missing"],
        sources: [],
        libs: [],
        ldflags: [],
        out: p"bad",
        deps: [],
      },
    ],
  }) {
    Ok(_) => test.eq("missing group accepted", "missing group rejected")?
    Err(_) => {}
  }

  let src_tree = test.temp_dir(ctx, name: "make-src-tree")?
  fs.mkdir(fp"${src_tree}/sub")?

  fs.write(
    fp"${src_tree}/main.c",
    """int main(void) { return 0; }
""",
  )?

  fs.write(
    fp"${src_tree}/skip.c",
    """int skip(void) { return 0; }
""",
  )?

  fs.write(
    fp"${src_tree}/sub/util.c",
    """int util(void) { return 0; }
""",
  )?

  fs.write(
    fp"${src_tree}/sub/readme.txt",
    """ignore
""",
  )?

  let discovered = make.discover_sources(src_tree, ["c"], [p"skip.c"])?
  test.eq([item.display() for item in discovered], ["main.c", "sub/util.c"])?
  let headers = test.temp_dir(ctx, name: "make-headers")?
  let header_out = test.temp_dir(ctx, name: "make-header-out")?
  fs.mkdir(fp"${headers}/sub")?

  fs.write(
    fp"${headers}/api.h",
    """api
""",
  )?

  fs.write(
    fp"${headers}/sub/private.h",
    """private
""",
  )?

  make.install_header_tree(headers, header_out, [p"sub/private.h"])?

  test.eq(
    fp"${header_out}/api.h".read_text()?,
    """api
""",
  )?

  test.eq(fp"${header_out}/sub/private.h".exists()?, false)?

  helper.write(r"""#!/bin/xsh --
proc count_value(path: Path) [fs, error] -> Result[Int] {
  if path.exists()? {
    return path.read_text()?.parse_int()?
  }

  0
}

proc main(mode: Str, ...argv: List[Str]) [fs, time, error] {
  match mode {
    "write" => {
      fs.write(fp"${argv[0]}", argv[1])?
    }
    "copy-append" => {
      fs.write(fp"${argv[1]}", fp"${argv[0]}".read_text()? + argv[2])?
    }
    "sleep-write" => {
      time.sleep(250ms)?
      fs.write(fp"${argv[0]}", argv[1])?
    }
    "compile" => {
      let count_path = fp"${argv[0]}"
      let next = count_value(count_path)? + 1
      fs.write(count_path, f"${next}")?
      fs.write(fp"${argv[1]}", f"object ${next}")?
      fs.write(fp"${argv[2]}", f"${argv[1]}: ${argv[3]} ${argv[4]}\n")?
    }
    "stamp" => {
      let count_path = fp"${argv[0]}"
      let next = count_value(count_path)? + 1
      fs.write(count_path, f"${next}")?
      fs.write(fp"${argv[1]}", argv[2])?
    }
    _ => abort(2)
  }
}

main(@args)?
""")?

  helper.chmod(0o755)?

  env {
    MAKEFLAGS = "-j2"
  } {
    test.eq(make.jobs()?, 2)?
    let order_root_handle = fs.tempdir()?
    defer fs.close_root(order_root_handle)?
    let order_root = fs.root_path(order_root_handle)?
    let first = fp"${order_root}/first.txt"
    let second = fp"${order_root}/second.txt"

    let first_task = make_helper_task(
      "first",
      order_root,
      [first],
      [],
      [],
      helper,
      "write",
      [first.display(), "first"],
      fp"${order_root}/first.cmd",
    )

    let second_task = make_helper_task(
      "second",
      order_root,
      [second],
      [first],
      ["first"],
      helper,
      "copy-append",
      [first.display(), second.display(), "second"],
      fp"${order_root}/second.cmd",
    )

    make.run_tasks([second_task, first_task], 2)?
    test.eq(second.read_text()?, "firstsecond")?
    let parallel_root_handle = fs.tempdir()?
    defer fs.close_root(parallel_root_handle)?
    let parallel_root = fs.root_path(parallel_root_handle)?
    let one = fp"${parallel_root}/one.txt"
    let two = fp"${parallel_root}/two.txt"

    let one_task = make_helper_task(
      "one",
      parallel_root,
      [one],
      [],
      [],
      helper,
      "sleep-write",
      [one.display(), "one"],
      fp"${parallel_root}/one.cmd",
    )

    let two_task = make_helper_task(
      "two",
      parallel_root,
      [two],
      [],
      [],
      helper,
      "sleep-write",
      [two.display(), "two"],
      fp"${parallel_root}/two.cmd",
    )

    let start = time.now()
    make.run_tasks([one_task, two_task], 2)?
    let elapsed = time.now() - start
    test.ok(elapsed < 800, f"parallel make tasks took ${elapsed}ms")?
    test.eq(one.read_text()?, "one")?
    test.eq(two.read_text()?, "two")?
    let dep_root_handle = fs.tempdir()?
    defer fs.close_root(dep_root_handle)?
    let dep_root = fs.root_path(dep_root_handle)?
    let src = fp"${dep_root}/main.c"
    let header = fp"${dep_root}/main.h"
    let dep_out = fp"${dep_root}/main.o"
    let depfile = fp"${dep_root}/main.o.d"
    let dep_stamp = fp"${dep_root}/main.o.cmd"
    let dep_count = fp"${dep_root}/count.txt"

    src.write("""source
""")?

    header.write("""header one
""")?

    let dep_task = make_helper_task(
      "compile",
      dep_root,
      [dep_out],
      [src],
      [],
      helper,
      "compile",
      [dep_count.display(), dep_out.display(), depfile.display(), src.display(), header.display()],
      dep_stamp,
      depfile,
    )

    make.run_tasks([dep_task], 1)?
    make.run_tasks([dep_task], 1)?
    test.eq(dep_count.read_text()?, "1")?

    header.write("""header two
""")?

    dep_out.touch_from(fp"${dep_dir()}/PKGBUILD.xsh")?
    make.run_tasks([dep_task], 1)?
    test.eq(dep_count.read_text()?, "2")?
    let stamp_root_handle = fs.tempdir()?
    defer fs.close_root(stamp_root_handle)?
    let stamp_root = fs.root_path(stamp_root_handle)?
    let artifact = fp"${stamp_root}/artifact.txt"
    let stamp_count = fp"${stamp_root}/count.txt"
    let stamp = fp"${stamp_root}/artifact.cmd"

    let stamp_first = make_helper_task(
      "artifact",
      stamp_root,
      [artifact],
      [],
      [],
      helper,
      "stamp",
      [stamp_count.display(), artifact.display(), "one"],
      stamp,
    )

    let stamp_second = make_helper_task(
      "artifact",
      stamp_root,
      [artifact],
      [],
      [],
      helper,
      "stamp",
      [stamp_count.display(), artifact.display(), "two"],
      stamp,
    )

    make.run_tasks([stamp_first], 1)?
    make.run_tasks([stamp_first], 1)?
    test.eq(stamp_count.read_text()?, "1")?
    make.run_tasks([stamp_second], 1)?
    test.eq(stamp_count.read_text()?, "2")?
    test.eq(artifact.read_text()?, "two")?
  } ?
}

proc expect_make_error(result: Result[Unit]) [error] {
  match result {
    Ok(_) => test.ok(false, "expected make error")?
    Err(_) => {}
  }
}

proc test_make_runner_rejects_invalid_graphs(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "make-invalid-root")?
  let out_a = fp"${root}/a.txt"
  let out_b = fp"${root}/b.txt"
  let base = make_helper_task("base", root, [out_a], [], [], /bin/true, "unused", [], fp"${root}/base.cmd")

  let missing_dep = make_helper_task(
    "missing",
    root,
    [out_b],
    [],
    ["absent"],
    /bin/true,
    "unused",
    [],
    fp"${root}/missing.cmd",
  )

  expect_make_error(make.run_tasks([base, missing_dep], 1))?

  let duplicate_output = make_helper_task(
    "duplicate",
    root,
    [out_a],
    [],
    [],
    /bin/true,
    "unused",
    [],
    fp"${root}/duplicate.cmd",
  )

  expect_make_error(make.run_tasks([base, duplicate_output], 1))?

  let cycle_a = make_helper_task(
    "cycle-a",
    root,
    [out_a],
    [],
    ["cycle-b"],
    /bin/true,
    "unused",
    [],
    fp"${root}/cycle-a.cmd",
  )

  let cycle_b = make_helper_task(
    "cycle-b",
    root,
    [out_b],
    [],
    ["cycle-a"],
    /bin/true,
    "unused",
    [],
    fp"${root}/cycle-b.cmd",
  )

  expect_make_error(make.run_tasks([cycle_a, cycle_b], 1))?
}
