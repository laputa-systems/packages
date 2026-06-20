pure xsh_bin() -> Path {
  return p"xsh"
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
  test.contains(output, "baseinit baseinit-2.0.0-1 5 built")?
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

proc test_pm_info_waterfox_bin_excludes_session_stack(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "waterfox-info-root")?
  let work = test.temp_dir(ctx, name: "waterfox-info-work")?
  let out = test.temp_dir(ctx, name: "waterfox-info-out")?
  let db = fp"${root}/var/lib/xsh-pm/packages/waterfox-bin"
  let no_mkdeps: List[Str] = []
  let no_etcsums: List[Record] = []
  fs.mkdir(db)?

  json.write(
    fp"${db}/metadata.json",
    {
      name: "waterfox-bin",
      ver: "140.11.0esr",
      rel: "1",
      deps: ["musl", "ca-certificates"],
      mkdeps: no_mkdeps,
      nostrip: true,
      dir: "repo/waterfox-bin",
    },
  )?

  json.write(fp"${db}/manifest.json", ["opt/waterfox/waterfox-bin", "usr/bin/waterfox"])?
  json.write(fp"${db}/etcsums.json", no_etcsums)?
  let info = run.text xsh_bin() pm.xsh -- info $root $work $out waterfox-bin ?
  test.contains(info, "waterfox-bin 140.11.0esr-1")?
  test.contains(info, "deps musl ca-certificates")?
  test.contains(info, "mkdeps")?

  for term in waterfox_forbidden_pm_info_terms() {
    test.eq(term in info, false, message: f"pm info unexpectedly contained ${term}")?
  }
}

proc test_pm_install_remove_lifecycle(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let install_out = run.text xsh_bin() pm.xsh -- install $root $work $out dep_dir() app_dir() ?
  test.contains(install_out, "dep dep-1.0.0-1 1 built")?
  test.contains(install_out, "app app-1.0.0-1 1 built")?

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
  test.contains(output, "extract-tree extract-tree-1.0.0-1 3 built")?
  test.contains(output, "extract-tree 3 ")?

  test.eq(
    fp"${root}/etc/extract-tree.conf".read_text()?,
    """extract-tree
""",
  )?

  test.eq(fp"${root}/empty-dir".metadata()?.kind, "dir")?
  test.eq(fp"${root}/empty-dir/.keep".exists()?, false)?
  test.eq(fp"${root}/bin".metadata()?.kind, "symlink")?
  test.eq(fp"${root}/bin".readlink()?.display(), "usr/bin")?
  test.eq(fp"${root}/usr/bin/extract-tree".metadata()?.mode % 4096, 0o755)?
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
  let checksum_out = run.text xsh_bin() pm.xsh -- checksum $root $work $out $pkg ?
  test.contains(checksum_out, "source-pkg 6667b2d1aab6a00caa5aee5af8ad9f1465e567abf1c209d15727d57b3e8f6e5f")?
  let update_out = run.text xsh_bin() pm.xsh -- update-checksums $root $work $out $pkg ?
  test.contains(update_out, "source-pkg checksums updated")?
  let pkgbuild = fp"${pkg}/PKGBUILD.xsh".read_text()?
  test.contains(pkgbuild, "6667b2d1aab6a00caa5aee5af8ad9f1465e567abf1c209d15727d57b3e8f6e5f")?
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
  let repo_index_text = fp"${repo}/index.json".read_text()?
  test.contains(repo_index_text, "\"name\":\"remote-app\"")?
  let refresh_out = run.text XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- refresh-index $install_root $install_work $install_out ?
  test.contains(refresh_out, "remote-index 1 refreshed")?
  let remote_install_out = run.text XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- install $install_root $install_work $install_out remote-app ?
  test.contains(remote_install_out, "remote-app 1 remote-installed")?

  test.eq(
    fp"${install_root}/usr/share/remote-app/payload.txt".read_text()?,
    """remote-app
""",
  )?
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
    f"""[{"arch":"${arch}","name":"evil","ver":"1.0.0","rel":"1","deps":[],"mkdeps":[],"target_build_deps":[],"sha256":"","size":1,"tarball":"../escape.tar.gz","metadata":"metadata/${arch}/evil/evil-1.0.0-1.json","source_sha256":"","source_tarball":"","metapackage":false}]
""",
  )?

  let refresh_out = run.text XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- refresh-index $root $work $out ?
  test.contains(refresh_out, "remote-index 1 refreshed")?
  let status = run.status XSH_PM_PUBLIC_REPO=$repo_url xsh_bin() pm.xsh -- install $root $work $out evil 2> $err
  test.eq(status.ok, false)?
  test.contains(err.read_text()?, "remote tarball must stay relative")?
  test.eq(fp"${out}/escape.tar.gz".exists()?, false)?
}

proc test_pm_lifecycle_hooks(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let hook_log = test.temp_path(ctx, name: "hooks.log")
  let hook = test.temp_path(ctx, name: "pm-hook")

  fs.write(
    hook,
    """#!/bin/sh
printf '%s|%s|%s\\n' "$XSH_PM_HOOK" "$XSH_PM_PACKAGE" "$XSH_PM_ACTION" >> "$HOOK_LOG"
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
  test.contains(output, "published")?
  test.ok(fp"${repo}/index.json".exists()?)?
  let arch = fixture_arch()?
  test.ok(fp"${repo}/packages/${arch}/baseinit/baseinit-2.0.0-1.tar.gz".exists()?)?
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
  let help = run.text ./pm.xsh "-h" ?
  test.contains(help, "usage: pm COMMAND [ARG...]")?

  test.contains(
    help,
    "world-plan PKGDIR... [--arch ARCH] [--build] [--upload] [--sync-rels] [--to-tranche N] [-j N|--jobs N]",
  )?

  let world_help = run.text ./pm.xsh world-plan "--help" ?
  test.contains(world_help, "usage: pm world-plan ...PKGDIR [OPTIONS]")?
  test.contains(world_help, "--arch ARCH")?
  test.contains(world_help, "--sync-rels")?
  test.contains(world_help, "--to-tranche N")?
}

proc test_pm_requires_package_proof(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "root")?
  let work = test.temp_dir(ctx, name: "work")?
  let out = test.temp_dir(ctx, name: "out")?
  let pkg = test.temp_dir(ctx, name: "proofless")?
  let err = test.temp_path(ctx, name: "pm.err")

  fs.write(
    fp"${pkg}/PKGBUILD.xsh",
    """export let name = "proofless"
export let ver = "1.0.0"
export let rel = "1"
export let deps: List[Str] = []
export let mkdeps: List[Str] = []
export let sources: List[Path] = []
export let checksums: List[Str] = []

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  fs.write(fp"\${dest}/proofless.txt", "proofless\\n")?
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
    """export let name = "svcless"
export let ver = "1.0.0"
export let rel = "1"
export let deps: List[Str] = []
export let mkdeps: List[Str] = []
export let sources: List[Path] = []
export let checksums: List[Str] = []

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  fs.mkdir(fp"\${dest}/usr/lib/xinit/services")?
  fs.write(fp"\${dest}/usr/lib/xinit/services/svcless.xsh", "export let service = {}\\n")?
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
  let output = run.text HOME=$home XSH_PM_BUILD_CHROOT=0 XSH_PM_REPO=$repo_url LAPUTA_TOKEN=token xsh_bin() pm.xsh -- world-plan world_pm_dir() world_lib_dir() world_app_dir() --build --upload --jobs 2 ?
  test.contains(output, "world-plan")?
  test.contains(output, f"world-repo ${home.display()}/.cache/laputa/world-")?
  test.contains(output, "jobs 2")?
  test.contains(output, "tranche 0")?
  test.contains(output, "tranche 1")?
  test.ok(! output.contains("`--"))?
  test.ok(! output.contains("after "))?
  test.contains(output, "world-lib proof ok")?
  test.contains(output, "world-app proof ok")?
  test.contains(output, "world-plan build complete")?
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
}

proc test_pm_world_plan_build_to_tranche_and_resume(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let first = run.text HOME=$home XSH_PM_BUILD_CHROOT=0 XSH_PM_OFFLINE=1 xsh_bin() pm.xsh -- world-plan world_pm_dir() world_lib_dir() world_app_dir() --build --to-tranche 1 --jobs 1 ?
  test.contains(first, "world-plan build paused at tranche 1")?
  let stage = single_world_cache(home)?
  let arch = fixture_arch()?
  test.ok(fp"${stage}/packages/${arch}/world-lib/world-lib-1.0.0-1.tar.gz".exists()?)?
  test.ok(! fp"${stage}/packages/${arch}/world-app/world-app-1.0.0-1.tar.gz".exists()?)?
  test.contains(fp"${stage}/.world/state.json".read_text()?, "\"complete\":false")?
  let second = run.text HOME=$home XSH_PM_BUILD_CHROOT=0 XSH_PM_OFFLINE=1 xsh_bin() pm.xsh -- world-plan world_pm_dir() world_lib_dir() world_app_dir() --build --jobs 1 ?
  test.contains(second, "world-lib world-lib-1.0.0-1 staged")?
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
  test.ok(! output.contains("remote same"))?
  test.ok(! output.contains("remote newer"))?
  test.ok(! output.contains("->"))?
}

proc test_pm_world_plan_displays_remote_to_local_catchup(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let repo = test.temp_dir(ctx, name: "repo")?
  let repo_url = f"file://${repo.display()}"
  let arch = fixture_arch()?
  let no_deps: List[Str] = []
  let no_mkdeps: List[Str] = []

  json.write(
    fp"${repo}/index.json",
    [
      {
        arch,
        name: "laputa-pm",
        ver: "1.0.0",
        rel: "0",
        deps: no_deps,
        mkdeps: no_mkdeps,
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
  test.contains(output, "laputa-pm 1.0.0-0 -> 1.0.0-1")?
  test.ok(! output.contains("remote newer"))?
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
  let no_deps: List[Str] = []
  let no_mkdeps: List[Str] = []
  let lib_deps: List[Str] = ["laputa-pm"]
  let app_deps: List[Str] = ["world-lib"]

  json.write(
    fp"${repo}/index.json",
    [
      {
        arch,
        name: "laputa-pm",
        ver: "1.0.0",
        rel: "0",
        deps: no_deps,
        mkdeps: no_mkdeps,
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
        mkdeps: no_mkdeps,
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
        mkdeps: no_mkdeps,
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

  let output = run.text HOME=$home NO_COLOR=1 XSH_PM_REPO=$repo_url xsh_bin() pm.xsh -- world-plan world_pm_dir() world_lib_dir() world_app_dir() ?
  test.contains(output, "laputa-pm 1.0.0-0 -> 1.0.0-1")?
  test.contains(output, "world-lib 1.0.0-1 -> 1.0.0-2")?
  test.contains(output, "world-app 1.0.0-1 -> 1.0.0-2")?
  test.ok(! output.contains("remote same"))?
  test.ok(! output.contains("remote newer"))?
}

proc test_pm_world_plan_autobumps_rel_for_changed_metadata(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let remote = test.temp_dir(ctx, name: "world-remote")?
  let repo_url = f"file://${remote.display()}"
  let arch = fixture_arch()?
  let no_deps: List[Str] = []
  let no_mkdeps: List[Str] = []
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
        mkdeps: no_mkdeps,
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

  let output = run.text HOME=$home XSH_PM_BUILD_CHROOT=0 XSH_PM_REPO=$repo_url xsh_bin() pm.xsh -- world-plan world_pm_dir() --build --jobs 1 ?
  test.contains(output, "laputa-pm 1.0.0-3")?
  let stage = single_world_cache(home)?
  test.ok(fp"${stage}/packages/${arch}/laputa-pm/laputa-pm-1.0.0-3.tar.gz".exists()?)?
  test.ok(fp"${stage}/metadata/${arch}/laputa-pm/laputa-pm-1.0.0-3.json".exists()?)?
  test.contains(fp"${stage}/index.json".read_text()?, "\"rel\":\"3\"")?
}

proc test_pm_world_plan_sync_rels_updates_pkgbuilds_after_upload(ctx: TestContext) [fs, process, env, error] {
  let home = test.temp_dir(ctx, name: "home")?
  let remote = test.temp_dir(ctx, name: "world-remote")?
  let pkg = test.temp_dir(ctx, name: "world-pm-copy")?
  let repo_url = f"file://${remote.display()}"
  let arch = fixture_arch()?
  let no_deps: List[Str] = []
  let no_mkdeps: List[Str] = []
  let metadata_rel = fp"metadata/${arch}/laputa-pm/laputa-pm-1.0.0-2.json"
  let _ = fs.copy_tree(world_pm_dir(), pkg, parents: true, overwrite: true)?
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
        mkdeps: no_mkdeps,
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

  let synced = run.text HOME=$home XSH_PM_BUILD_CHROOT=0 XSH_PM_REPO=$repo_url LAPUTA_TOKEN=token xsh_bin() pm.xsh -- world-plan $pkg --build --upload --sync-rels --jobs 1 ?
  test.contains(synced, "laputa-pm 1.0.0-1 -> 1.0.0-3 rel-synced")?
  test.contains(fp"${pkg}/PKGBUILD.xsh".read_text()?, "export let rel: Str = \"3\"")?
  let output = run.text HOME=$home NO_COLOR=1 XSH_PM_REPO=$repo_url xsh_bin() pm.xsh -- world-plan $pkg ?
  test.contains(output, "laputa-pm 1.0.0-3")?
  test.ok(! output.contains("->"))?
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
    """#!/bin/sh
# ignored summary
""",
  )?

  fs.write(
    shadow_first,
    """#!/bin/sh
# first summary
""",
  )?

  fs.write(
    shadow_second,
    """#!/bin/sh
# second summary
""",
  )?

  fs.write(
    plain,
    """#!/bin/sh
not a comment summary
""",
  )?

  shadow_first.chmod(0o755)?
  shadow_second.chmod(0o755)?
  plain.chmod(0o755)?
  let path_text = f"${first.display()}:${second.display()}:${env.get("PATH")?}"
  let help = run.text PATH=$path_text xsh_bin() pm.xsh -- help-ext $root $work $out ?
  test.contains(help, "extension shadow first summary")?
  test.eq(help.contains("ignored"), false)?
  test.eq(help.contains("second summary"), false)?
  test.eq(help.contains("not a comment summary"), false)?
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
    """#!/bin/sh
{
  printf 'root=%s
' "$XSH_PM_ROOT"
  printf 'work=%s
' "$XSH_PM_WORK"
  printf 'out=%s
' "$XSH_PM_OUT"
  printf 'action=%s
' "$XSH_PM_ACTION"
  printf 'args=<%s>
' "$XSH_PM_ARGS"
} > "$EXT_LOG"
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
  test.contains(upload_meta, "remote-meta 1.0.0-1 published")?
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

proc test_make_runner_behaviors(ctx: TestContext) [fs, process, error] {
  let script = test.temp_path(ctx, name: "make-runner.xsh")

  script.write(
    """use pm.make

pure shell_task(
  name: Str,
  cwd: Path,
  outputs: List[Path],
  inputs: List[Path],
  deps: List[Str],
  script: Str,
  stamp: Path,
  depfile: Path = Path(""),
) -> make.MakeTask {
  return {
    name: name,
    outputs: outputs,
    inputs: inputs,
    deps: deps,
    argv: ["/bin/sh", "-c", script],
    cwd: cwd,
    env: {},
    depfile: depfile,
    stamp: stamp,
  }
}

proc main() [fs, process, time, env, error] {
  test.eq(make.jobs()?, 2)?

  let order_root_handle = fs.tempdir()?
  defer fs.close_root(order_root_handle)?
  let order_root = fs.root_path(order_root_handle)?
  let first = fp"\${order_root}/first.txt"
  let second = fp"\${order_root}/second.txt"
  let first_task = shell_task("first", order_root, [first], [], [], f"printf first > \${first.display()}", fp"\${order_root}/first.cmd")
  let second_task = shell_task("second", order_root, [second], [first], ["first"], f"cat \${first.display()} > \${second.display()}; printf second >> \${second.display()}", fp"\${order_root}/second.cmd")
  make.run_tasks([second_task, first_task], 2)?
  test.eq(second.read_text()?, "firstsecond")?

  let parallel_root_handle = fs.tempdir()?
  defer fs.close_root(parallel_root_handle)?
  let parallel_root = fs.root_path(parallel_root_handle)?
  let one = fp"\${parallel_root}/one.txt"
  let two = fp"\${parallel_root}/two.txt"
  let one_task = shell_task("one", parallel_root, [one], [], [], f"sleep 1; printf one > \${one.display()}", fp"\${parallel_root}/one.cmd")
  let two_task = shell_task("two", parallel_root, [two], [], [], f"sleep 1; printf two > \${two.display()}", fp"\${parallel_root}/two.cmd")
  let start = time.now()
  make.run_tasks([one_task, two_task], 2)?
  let elapsed = time.now() - start
  test.ok(elapsed < 1800, f"parallel make tasks took \${elapsed}ms")?
  test.eq(one.read_text()?, "one")?
  test.eq(two.read_text()?, "two")?

  let dep_root_handle = fs.tempdir()?
  defer fs.close_root(dep_root_handle)?
  let dep_root = fs.root_path(dep_root_handle)?
  let src = fp"\${dep_root}/main.c"
  let header = fp"\${dep_root}/main.h"
  let dep_out = fp"\${dep_root}/main.o"
  let depfile = fp"\${dep_root}/main.o.d"
  let dep_stamp = fp"\${dep_root}/main.o.cmd"
  let dep_count = fp"\${dep_root}/count.txt"
  src.write("source\\n")?
  header.write("header one\\n")?
  let dep_script = f"n=0\\nif [ -f \${dep_count.display()} ]; then n=$(cat \${dep_count.display()}); fi\\nn=$((n + 1))\\nprintf '%s' \\"$n\\" > \${dep_count.display()}\\nprintf 'object %s' \\"$n\\" > \${dep_out.display()}\\nprintf '%s: %s %s\\\\n' \${dep_out.display()} \${src.display()} \${header.display()} > \${depfile.display()}\\n"
  let dep_task = shell_task("compile", dep_root, [dep_out], [src], [], dep_script, dep_stamp, depfile)
  make.run_tasks([dep_task], 1)?
  make.run_tasks([dep_task], 1)?
  test.eq(dep_count.read_text()?, "1")?
  time.sleep(1100ms)?
  header.write("header two\\n")?
  make.run_tasks([dep_task], 1)?
  test.eq(dep_count.read_text()?, "2")?

  let stamp_root_handle = fs.tempdir()?
  defer fs.close_root(stamp_root_handle)?
  let stamp_root = fs.root_path(stamp_root_handle)?
  let artifact = fp"\${stamp_root}/artifact.txt"
  let stamp_count = fp"\${stamp_root}/count.txt"
  let stamp = fp"\${stamp_root}/artifact.cmd"
  let script_one = f"n=0\\nif [ -f \${stamp_count.display()} ]; then n=$(cat \${stamp_count.display()}); fi\\nn=$((n + 1))\\nprintf '%s' \\"$n\\" > \${stamp_count.display()}\\nprintf one > \${artifact.display()}\\n"
  let script_two = f"n=0\\nif [ -f \${stamp_count.display()} ]; then n=$(cat \${stamp_count.display()}); fi\\nn=$((n + 1))\\nprintf '%s' \\"$n\\" > \${stamp_count.display()}\\nprintf two > \${artifact.display()}\\n"
  let stamp_first = shell_task("artifact", stamp_root, [artifact], [], [], script_one, stamp)
  let stamp_second = shell_task("artifact", stamp_root, [artifact], [], [], script_two, stamp)
  make.run_tasks([stamp_first], 1)?
  make.run_tasks([stamp_first], 1)?
  test.eq(stamp_count.read_text()?, "1")?
  make.run_tasks([stamp_second], 1)?
  test.eq(stamp_count.read_text()?, "2")?
  test.eq(artifact.read_text()?, "two")?
}

main()?
""",
  )?

  let module_path = fs.cwd()?.display()
  run.text XSH_MODULE_PATH=$module_path MAKEFLAGS="-j2" xsh_bin() $script ?
}
