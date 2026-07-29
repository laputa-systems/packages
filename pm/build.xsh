use extensions
use local
use pm.env as pm_env
use pm.proof as pm_proof
use sources
use types
use util

export proc write_proof_receipt(out: Path, pkg: Package, tarball: Path) [fs, error] {
  let receipt = proof_receipt_path(out, pkg)
  fs.mkdir(receipt.parent)?

  json.write(
    receipt,
    {
      format: "laputa-package-proof-1",
      name: pkg.name,
      ver: pkg.ver,
      rel: pkg.rel,
      tarball_sha256: hash.sha256(tarball)?.hex(),
    },
  )?
}

pure source_fingerprint_input(rel: Path) -> Bool {
  let name = rel.name
  let key = rel.display()

  if name.starts_with("PKGBUILD") {
    return true
  }

  if key.starts_with("files/") or key.starts_with("patches/") {
    return true
  }

  return ! name.ends_with(".xsh")
}

proc source_ready_fingerprint(pkg: Package) [fs, env, error] -> Result[Str] {
  let arch = util.target_arch()?
  var body = f"""${pkg.name}	${pkg.ver}	${pkg.rel}	${arch}
"""

  for entry in fs.walk(pkg.dir) |> sort-by .path {
    if entry.kind == "file" {
      let rel = entry.path.strip_prefix(pkg.dir)?

      if source_fingerprint_input(rel) {
        body = f"""${body}${rel.display()}	${hash.sha256(entry.path)?.hex()}
"""
      }
    }
  }

  bytes.from_text(body).sha256().hex()
}

proc prepare_build_package_source(ctx: PmContext, pkg: Package) [fs, net, process, env, time, error] {
  let id = package_id(pkg.name, pkg.ver, pkg.rel)
  let pkg_work = fp"${ctx.work}/${id}"
  let src = fp"${pkg_work}/src"
  let reuse_work = (env.get("XSH_PM_REUSE_WORK") ?? "") == "1"
  let source_ready = fp"${pkg_work}/.source-ready"
  let source_fingerprint = source_ready_fingerprint(pkg)?
  let source_is_ready = fs.exists(source_ready)? and source_ready.read_text()?.trim() == source_fingerprint

  if ! reuse_work {
    fs.remove(pkg_work, missing_ok: true)?
  }

  if ! reuse_work or ! src.exists()? or ! source_is_ready {
    fs.remove(src, missing_ok: true)?

    if pkg.upstream_sources.len() == 0 {
      fs.mkdir(src)?
    }

    prepare_package_source_tree(ctx.work, ctx.out, pkg, src, false, true, ! reuse_work)?

    fs.write(source_ready, source_fingerprint)?
  }
}

proc chroot_build_enabled(ctx: PmContext) [env] -> Bool {
  if (env.get("XSH_PM_IN_CHROOT") ?? "") == "1" {
    return false
  }

  if (env.get("XSH_PM_BUILD_CHROOT") ?? "1") == "0" {
    return false
  }

  return ctx.command == "build-install" or ctx.command == "world-plan" or ctx.command == "build-set"
}

proc pm_source_root() [fs, env, error] -> Result[Path] {
  let module_path = env.get("XSH_MODULE_PATH") ?? "/usr/lib/pm"

  for entry in module_path.split(":") {
    let root = fp"${entry}"

    if fs.exists(fp"${root}/pm.xsh")? and fs.exists(fp"${root}/pm")? {
      return root
    }
  }

  for candidate in [p"laputa", p"."] {
    if fs.exists(fp"${candidate}/pm.xsh")? and fs.exists(fp"${candidate}/pm")? {
      return path.absolute(candidate)?
    }
  }

  return /usr/lib/pm
}

pure seeded_shell_script() -> Str {
  return r"""#!/bin/xsh
error ShError = Failed(message: Str)

proc run_argv(argv: List[Str]) [process, error] {
  if argv.len() == 0 {
    return
  }

  let status = process.run(process.command_argv(argv[0], argv))?

  if ! status.ok {
    let rendered = argv.join(" ")
    Err(ShError.Failed(message: f"command failed: ${rendered}"))?
  }
}

proc run_command_list(script: Str) [process, error] {
  for part in script.split("&&") {
    let command = part.trim()
    continue when command == "" or command == ":"
    run_argv(process.argv_words(command)?)?
  }
}

proc run_xshi(argv: List[Str]) [process, error] {
  let xshi_argv = ["/bin/xshi"].extend(argv)
  let status = process.run(process.command_argv("/bin/xshi", xshi_argv))?

  if ! status.ok {
    Err(ShError.Failed(message: "xshi failed"))?
  }
}

proc main(...argv: List[Str]) [process, error] {
  if argv.len() >= 2 and argv[0] == "-c" {
    run_command_list(argv[1])?
  } else {
    run_xshi(argv)?
  }
}

main(@args)?
"""
}

proc seed_chroot_runner(root: Path) [fs, process, env, error] {
  let xsh = xsh_runner()?
  seed_xsh_multicall(root, xsh)?

  if fs.exists(/usr/lib/xsh)? {
    let _ = fs.copy_tree(/usr/lib/xsh, fp"${root}/usr/lib/xsh", parents: true, overwrite: true)?
  }

  let pm_root = pm_source_root()?
  fs.install(fp"${pm_root}/pm.xsh", fp"${root}/usr/lib/pm/pm.xsh", 0o644, parents: true, overwrite: true)?
  fs.remove(fp"${root}/usr/lib/pm/pm", missing_ok: true)?
  let _ = fs.copy_tree(fp"${pm_root}/pm", fp"${root}/usr/lib/pm/pm", parents: true, overwrite: true)?

  for sh in [fp"${root}/usr/bin/sh", fp"${root}/bin/sh"] {
    fs.mkdir(sh.parent)?
    fs.remove(sh, missing_ok: true)?
    fs.write(sh, seeded_shell_script())?
    fs.chmod(sh, 0o755)?
  }

  for tmp in [fp"${root}/tmp", fp"${root}/var/tmp"] {
    fs.mkdir(tmp)?
    fs.chmod(tmp, 0o1777)?
  }

  fs.mkdir(fp"${root}/proc")?

  for name in ["cpuinfo", "meminfo"] {
    let source = fp"/proc/${name}"
    let dest = fp"${root}/proc/${name}"

    match fs.metadata(source) {
      Ok(metadata) if metadata.kind == "file" => fs.copy(source, dest, overwrite: true)?
      _ => {
        if ! fs.exists(dest)? {
          fs.write(dest, "")?
        }
      }
    }
  }

  seed_chroot_device_paths(root)?
  fs.mkdir(fp"${root}/etc")?

  for name in ["resolv.conf", "hosts", "nsswitch.conf"] {
    let source = fp"/etc/${name}"
    let dest = fp"${root}/etc/${name}"

    match fs.metadata(source) {
      Ok(metadata) if metadata.kind == "file" => fs.copy(source, dest, overwrite: true)?
      Ok(metadata) if metadata.kind == "symlink" => fs.write(dest, source.read_text()?)?
      _ => {}
    }
  }
}

proc xsht_runner() [fs, process, env, error] -> Result[Path] {
  let xsh = xsh_runner()?
  let sibling = fp"${xsh.parent}/xsht"

  if fs.exists(sibling)? {
    return sibling
  }

  if fs.exists(/bin/xsht)? {
    return /bin/xsht
  }

  process.which("xsht")?
}

export proc build_prepared_package(pkg_dir: Path, src: Path, dest: Path, tarball: Path) [fs, process, env, error] {
  let packages = load_package_dirs([pkg_dir])?
  let pkg = packages[0]
  let makeflags = env.get("MAKEFLAGS") ?? f"-s -j${cpu.count()}"

  env {
    DESTDIR = dest
    LAPUTA_ROOT = "/"
    XSH_PM_PREFIX = pm_env.prefix
    XSH_PM_SYSCONFDIR = pm_env.sysconfdir
    XSH_PM_LOCALSTATEDIR = pm_env.localstatedir
    XSH_PM_LIBDIR = pm_env.libdir
    XSH_PM_LIBDIR_NAME = pm_env.libdir_name
    XSH_PM_BINDIR = pm_env.bindir
    XSH_PM_INCLUDEDIR = pm_env.includedir
    XSH_PM_MANDIR = pm_env.mandir
    XSH_PM_NAME = pkg.name
    XSH_PM_VERSION = pkg.ver
    XSH_PM_RELEASE = pkg.rel
    XSH_PM_QUIET = "1"
    MAKEFLAGS = makeflags
    SHELL = "/bin/xshi"
  } {
    let exports = pkg.exports
    let runner = fp"${pkg_dir}/run-package-build.xsh"

    let prepare_call = if exports.has("prepare") {
      """  prepare(src)?
"""
    } else {
      ""
    }

    let build_call = if exports.has("build") {
      """  cd src {
    build(dest)?
  } ?
"""
    } else {
      ""
    }

    let runner_text = """use PKGBUILD

proc main(src: Path, dest: Path) [fs, process, env, error] {
""" + prepare_call + """  fs.remove(dest, missing_ok: true)?
  fs.mkdir(dest)?
""" + build_call + """}
main(@args)?
"""

    fs.write(runner, runner_text)?
    let trace_path = fp"${pkg_dir.parent}/run-package-build.trace"
    let xsht = xsht_runner()?

    let status = process.run(
      process.command_argv(
        xsht,
        [
          xsht.display(),
          "trace",
          "--trace-file",
          trace_path.display(),
          runner.display(),
          "--",
          src.display(),
          dest.display(),
        ],
      ),
    )?

    if ! status.ok {
      if status.exited() {
        return Err(PmError.ExtensionFailed(f"package build for ${pkg.name} exited with status ${status.exit_code()?}"))
      }

      return Err(PmError.ExtensionFailed(f"package build for ${pkg.name} was signaled"))
    }
  } ?

  let manifest = fs.walk(dest)
    |> where .kind == "file" or .kind == "symlink"
    |> map { |entry|
      entry.path.strip_prefix(dest)?
    }
    |> sort-by .display()

  validate_and_strip_package(pkg, dest, manifest)?
  let etcsums = collect_etcsums(dest, manifest)?
  write_package_db(dest, pkg, manifest, etcsums)?
  let dest_text = dest.display()
  var archive_paths = []

  for entry in fs.walk(dest) {
    var include = entry.kind == "file" or entry.kind == "symlink"

    if pkg.extract_install and entry.kind == "dir" and entry.path.display() != dest_text and dir_empty(entry.path)? {
      include = true
    }

    if include {
      archive_paths = archive_paths.push(entry.path.strip_prefix(dest)?)
    }
  }

  archive_paths = archive_paths |> sort-by .display()
  fs.mkdir(tarball.parent)?
  archive.tar_create(tarball, dest, archive_paths, compression: "gz", overwrite: true)?
}

proc chroot_build_cache_dir(ctx: PmContext, pkg: Package) [] -> Path {
  return fp"${ctx.work}/.chroot-build-cache/${pkg.name}"
}

proc linux_kbuild_cache_files() [] -> List[Str] {
  return [
    ".xsh-kbuild-plan.json",
    ".xsh-kbuild-plan.fingerprint",
    ".xsh-kbuild-compile-flags.json",
    ".xsh-kbuild-archive-plan.json",
    ".xsh-kbuild-archive-plan.json.summary",
    ".xsh-kbuild-archive-plan.fingerprint",
  ]
}

proc seed_chroot_build_cache(ctx: PmContext, pkg: Package, src: Path) [fs, error] {
  if pkg.name != "linux" {
    return
  }

  let cache = chroot_build_cache_dir(ctx, pkg)

  for name in linux_kbuild_cache_files() {
    let cached = fp"${cache}/${name}"

    if cached.exists()? {
      fs.copy(cached, fp"${src}/${name}", overwrite: true)?
    }
  }
}

proc preserve_chroot_build_cache(ctx: PmContext, pkg: Package, src: Path) [fs, error] {
  if pkg.name != "linux" {
    return
  }

  let cache = chroot_build_cache_dir(ctx, pkg)
  fs.mkdir(cache)?

  for name in linux_kbuild_cache_files() {
    let source = fp"${src}/${name}"
    let cached = fp"${cache}/${name}"

    if source.exists()? {
      fs.copy(source, cached, overwrite: true)?
    } else {
      fs.remove(cached, missing_ok: true)?
    }
  }
}

proc run_chroot_build_command(
  host_xsh: Path,
  chroot_argv: List[Str],
  build_log_text: Str,
  build_log: Path,
) [fs, process, error] -> Result[Status] {
  if build_log_text != "" {
    fs.remove(build_log, missing_ok: true)?
    fs.mkdir(build_log.parent)?
    return process.run(process.command_argv(host_xsh, chroot_argv, stdout: build_log, stderr: build_log))
  }

  process.run(process.command_argv(host_xsh, chroot_argv))
}

proc append_build_log_or_print(build_log_text: Str, build_log: Path, line: Str) [fs, error] {
  if build_log_text == "" {
    print --flush $line
    return
  }

  let existing = if fs.exists(build_log)? { build_log.read_text()? } else { "" }
  fs.mkdir(build_log.parent)?

  fs.write(
    build_log,
    f"""${existing}${line}
""",
  )?
}

proc run_logged_proof_command(
  target: Path,
  argv: List[Str],
  build_log_text: Str,
  build_log: Path,
) [fs, process, error] {
  if build_log_text != "" {
    fs.mkdir(build_log.parent)?

    let status = process.run(
      process.command_argv(target, argv, stdout: build_log, stderr: build_log, stdout_append: true, stderr_append: true),
    )?

    if ! status.ok {
      if status.exited() {
        return Err(PmError.ExtensionFailed(f"package proof exited with status ${status.exit_code()?}"))
      }

      return Err(PmError.ExtensionFailed("package proof was signaled"))
    }

    return
  }

  let status = process.run(process.command_argv(target, argv))?

  if ! status.ok {
    if status.exited() {
      return Err(PmError.ExtensionFailed(f"package proof exited with status ${status.exit_code()?}"))
    }

    return Err(PmError.ExtensionFailed("package proof was signaled"))
  }
}

proc build_packages_in_chroot(
  ctx: PmContext,
  packages: List[Package],
) [fs, net, process, env, time, error] -> Result[List[BuiltPackage]] {
  var built = []
  var owners: Map[Str] = {}

  for pkg in packages {
    let source_started = time.now()
    print --flush "pm-build-phase-start" $pkg.name "source"
    prepare_build_package_source(ctx, pkg)?
    print --flush "pm-build-phase-done" $pkg.name "source" ${time.now() - source_started} "ms"
    seed_chroot_runner(ctx.root)?
    let id = package_id(pkg.name, pkg.ver, pkg.rel)
    let source_src = fp"${ctx.work}/${id}/src"
    let stage = fp"${ctx.root}/var/tmp/pm-build/${id}"
    let src = fp"${stage}/src"
    let pkg_dir = fp"${stage}/pkg"
    let dest = fp"${stage}/dest"
    let source_ready_path = fp"${ctx.work}/${id}/.source-ready"
    let source_copy_ready_path = fp"${stage}/.source-copy-ready"
    let chroot_stage = fp"/var/tmp/pm-build/${id}"
    let chroot_pkg = fp"${chroot_stage}/pkg"
    let chroot_src = fp"${chroot_stage}/src"
    let chroot_dest = fp"${chroot_stage}/dest"
    let chroot_tarball = fp"${chroot_stage}/out/${id}.tar.gz"
    let host_tarball = fp"${stage}/out/${id}.tar.gz"
    let tarball = fp"${ctx.out}/${id}.tar.gz"
    let chroot_root = ctx.root
    let host_xsh = xsh_runner()?
    let host_chroot_runner = fp"${pm_source_root()?}/pm/chroot-run.xsh"
    let build_log_text = (env.get("XSH_PM_BUILD_LOG") ?? "").trim()
    let build_log = fp"${build_log_text}"
    let makeflags = env.get("MAKEFLAGS") ?? f"-s -j${cpu.count()}"
    let build_arch = util.build_arch()?
    let target_arch = util.target_arch()?
    let source_copy_ready = (env.get("XSH_PM_REUSE_WORK") ?? "") == "1" and source_ready_path.exists()? and source_copy_ready_path.exists()? and source_ready_path.read_text()?.trim() == source_copy_ready_path.read_text()?.trim()

    if source_copy_ready {
      fs.remove(pkg_dir, missing_ok: true)?
      fs.remove(dest, missing_ok: true)?
      fs.remove(fp"${stage}/out", missing_ok: true)?
      fs.copy_tree(pkg.dir, pkg_dir, parents: true, overwrite: true)?
      print --flush "pm-build-phase-done" $pkg.name "source-copy" 0 "ms" "reused"
    } else {
      fs.remove(stage, missing_ok: true)?
      fs.mkdir(stage)?
      let copy_started = time.now()
      print --flush "pm-build-phase-start" $pkg.name "source-copy"
      fs.copy_tree(source_src, src, parents: true, overwrite: true)?
      fs.copy_tree(pkg.dir, pkg_dir, parents: true, overwrite: true)?
      fs.write(source_copy_ready_path, source_ready_path.read_text()?)?
      print --flush "pm-build-phase-done" $pkg.name "source-copy" ${time.now() - copy_started} "ms"
    }

    seed_chroot_build_cache(ctx, pkg, src)?
    run_lifecycle_hooks("pre-build", pkg.name, ctx, src.display())?

    let chroot_argv = [
      host_xsh.display(),
      host_chroot_runner.display(),
      "--",
      chroot_root.display(),
      pkg.name,
      "/bin/xsh",
      "/usr/lib/pm/pm.xsh",
      "--",
      "build-prepared-package",
      chroot_pkg.display(),
      chroot_src.display(),
      chroot_dest.display(),
      chroot_tarball.display(),
    ]

    env {
      LAPUTA_ROOT = "/"
      MAKEFLAGS = makeflags
      PATH = pm_env.build_path(/, "/bin:/usr/bin")
      XSH_PM_PREFIX = pm_env.prefix
      XSH_PM_SYSCONFDIR = pm_env.sysconfdir
      XSH_PM_LOCALSTATEDIR = pm_env.localstatedir
      XSH_PM_LIBDIR = pm_env.libdir
      XSH_PM_LIBDIR_NAME = pm_env.libdir_name
      XSH_PM_BINDIR = pm_env.bindir
      XSH_PM_INCLUDEDIR = pm_env.includedir
      XSH_PM_MANDIR = pm_env.mandir
      XSH_MODULE_PATH = "/usr/lib/pm"
      XSH_LINUX_REAL = "1"
      XSH_LINUX_KBUILD_DISCOVER_JOBS = env.get("XSH_LINUX_KBUILD_DISCOVER_JOBS") ?? ""
      XSH_LINUX_KBUILD_FORCE_ARCHIVES = env.get("XSH_LINUX_KBUILD_FORCE_ARCHIVES") ?? ""
      XSH_LINUX_KBUILD_JOBS = env.get("XSH_LINUX_KBUILD_JOBS") ?? ""
      XSH_LINUX_KBUILD_LOCAL_RECORDS = env.get("XSH_LINUX_KBUILD_LOCAL_RECORDS") ?? ""
      XSH_LINUX_KBUILD_LOCAL_RECORD_CACHE = env.get("XSH_LINUX_KBUILD_LOCAL_RECORD_CACHE") ?? ""
      XSH_LINUX_KBUILD_ONLY = env.get("XSH_LINUX_KBUILD_ONLY") ?? ""
      XSH_LINUX_KBUILD_PLAN = env.get("XSH_LINUX_KBUILD_PLAN") ?? ""
      XSH_LINUX_KBUILD_PROGRESS = env.get("XSH_LINUX_KBUILD_PROGRESS") ?? ""
      XSH_LINUX_KBUILD_PROGRESS_EVERY = env.get("XSH_LINUX_KBUILD_PROGRESS_EVERY") ?? "100"
      XSH_LINUX_KBUILD_REUSE_ARCHIVE_PLAN = env.get("XSH_LINUX_KBUILD_REUSE_ARCHIVE_PLAN") ?? ""
      XSH_LINUX_KBUILD_REUSE_ARCHIVES = env.get("XSH_LINUX_KBUILD_REUSE_ARCHIVES") ?? ""
      XSH_LINUX_KBUILD_STOP_AFTER = env.get("XSH_LINUX_KBUILD_STOP_AFTER") ?? ""
      XSH_LINUX_KBUILD_TIMING = env.get("XSH_LINUX_KBUILD_TIMING") ?? ""
      XSH_LINUX_KBUILD_TRUST_PLAN_CACHE = env.get("XSH_LINUX_KBUILD_TRUST_PLAN_CACHE") ?? ""
      XSH_LINUX_KBUILD_USE_PLAN = env.get("XSH_LINUX_KBUILD_USE_PLAN") ?? ""
      XSH_LINUX_KBUILD_USE_PLAN_TEXT = env.get("XSH_LINUX_KBUILD_USE_PLAN_TEXT") ?? ""
      XSH_MAKE_PROGRESS = env.get("XSH_MAKE_PROGRESS") ?? ""
      XSH_DISABLE_COMPACT_RUNNER = env.get("XSH_DISABLE_COMPACT_RUNNER") ?? "1"
      XSH_PM_ARCH = target_arch
      XSH_PM_BUILD_ARCH = build_arch
      XSH_PM_BUILD_ROOT = "/"
      XSH_PM_TARGET_ARCH = target_arch
      XSH_PM_IN_CHROOT = "1"
      SHELL = "/bin/xshi"
    } {
      let chroot_started = time.now()
      print --flush "pm-build-phase-start" $pkg.name "chroot"
      let status = run_chroot_build_command(host_xsh, chroot_argv, build_log_text, build_log)?
      print --flush "pm-build-phase-done" $pkg.name "chroot" ${time.now() - chroot_started} "ms"
      preserve_chroot_build_cache(ctx, pkg, src)?

      if ! status.ok {
        if status.exited() {
          return Err(PmError.ExtensionFailed(f"chroot build for ${pkg.name} exited with status ${status.exit_code()?}"))
        }

        return Err(PmError.ExtensionFailed(f"chroot build for ${pkg.name} was signaled"))
      }
    } ?

    fs.install(host_tarball, tarball, 0o644, parents: true, overwrite: true)?
    let item = load_built_package_from_dest(pkg, id, tarball, dest)?

    for rel_path in item.manifest {
      let key = rel_path.display()

      if owners.has(key) {
        let owner = owners.get(key)?
        return Err(PmError.PackageConflict(f"${pkg.name} conflicts with ${owner}: ${key}"))
      }

      owners[key] = pkg.name
    }

    run_package_proof(ctx, pkg, id, tarball, item.manifest, built, build_log_text, build_log)?
    write_proof_receipt(ctx.out, pkg, tarball)?
    run_lifecycle_hooks("post-build", pkg.name, ctx, tarball.display())?
    built = built.push(item)
    let tarball_size = fs.metadata(tarball)?.size

    append_build_log_or_print(
      build_log_text,
      build_log,
      f"${pkg.name} ${id} build: ${item.manifest.len()} files size: ${compressed_package_size(tarball_size)}",
    )?
  }

  built
}

export proc build_packages(
  ctx: PmContext,
  packages: List[Package],
) [fs, net, process, env, time, error] -> Result[List[BuiltPackage]] {
  if chroot_build_enabled(ctx) {
    return build_packages_in_chroot(ctx, packages)
  }

  var built = []
  var owners: Map[Str] = {}

  for pkg in packages {
    prepare_build_package_source(ctx, pkg)?
  }

  for pkg in packages {
    let id = package_id(pkg.name, pkg.ver, pkg.rel)
    let pkg_work = fp"${ctx.work}/${id}"
    let src = fp"${pkg_work}/src"
    let dest = fp"${pkg_work}/dest"
    let tarball = fp"${ctx.out}/${id}.tar.gz"
    run_lifecycle_hooks("pre-build", pkg.name, ctx, src.display())?
    let makeflags = env.get("MAKEFLAGS") ?? f"-s -j${cpu.count()}"

    env {
      DESTDIR = dest
      XSH_PM_PREFIX = pm_env.prefix
      XSH_PM_SYSCONFDIR = pm_env.sysconfdir
      XSH_PM_LOCALSTATEDIR = pm_env.localstatedir
      XSH_PM_LIBDIR = pm_env.libdir
      XSH_PM_LIBDIR_NAME = pm_env.libdir_name
      XSH_PM_BINDIR = pm_env.bindir
      XSH_PM_INCLUDEDIR = pm_env.includedir
      XSH_PM_MANDIR = pm_env.mandir
      XSH_PM_NAME = pkg.name
      XSH_PM_VERSION = pkg.ver
      XSH_PM_RELEASE = pkg.rel
      XSH_PM_QUIET = "1"
      MAKEFLAGS = makeflags
    } {
      let exports = pkg.exports

      if exports.has("prepare") {
        let prepare_fn: Proc = exports.get("prepare")?
        prepare_fn.call(src)?
      }

      fs.remove(dest, missing_ok: true)?
      fs.mkdir(dest)?

      if exports.has("build") {
        cd src {
          let build_fn: Proc = exports.get("build")?
          build_fn.call(dest)?
        } ?
      }
    } ?

    let manifest = fs.walk(dest)
      |> where .kind == "file" or .kind == "symlink"
      |> map { |entry|
        entry.path.strip_prefix(dest)?
      }
      |> sort-by .display()

    validate_and_strip_package(pkg, dest, manifest)?

    for rel_path in manifest {
      let key = rel_path.display()

      if owners.has(key) {
        let owner = owners.get(key)?
        return Err(PmError.PackageConflict(f"${pkg.name} conflicts with ${owner}: ${key}"))
      }

      owners[key] = pkg.name
    }

    let etcsums = collect_etcsums(dest, manifest)?
    write_package_db(dest, pkg, manifest, etcsums)?
    let dest_text = dest.display()
    var archive_paths = []

    for entry in fs.walk(dest) {
      var include = entry.kind == "file" or entry.kind == "symlink"

      if pkg.extract_install and entry.kind == "dir" and entry.path.display() != dest_text and dir_empty(entry.path)? {
        include = true
      }

      if include {
        archive_paths = archive_paths.push(entry.path.strip_prefix(dest)?)
      }
    }

    archive_paths = archive_paths |> sort-by .display()
    fs.mkdir(ctx.out)?
    archive.tar_create(tarball, dest, archive_paths, compression: "gz", overwrite: true)?
    run_package_proof(ctx, pkg, id, tarball, manifest, built, "", fp"")?
    write_proof_receipt(ctx.out, pkg, tarball)?
    run_lifecycle_hooks("post-build", pkg.name, ctx, tarball.display())?
    let metadata_files = collect_metadata_files(dest, manifest)?
    let metadata_sha256 = metadata_files_sha256(pkg, metadata_files)?
    let tarball_size = fs.metadata(tarball)?.size

    built = built.push({
      pkg,
      id,
      tarball,
      manifest,
      etcsums,
      metadata_sha256,
      metadata_files,
    })

    append_build_log_or_print(
      "",
      fp"",
      f"${pkg.name} ${id} build: ${manifest.len()} files size: ${compressed_package_size(tarball_size)}",
    )?
  }

  built
}

proc xsh_runner() [fs, process, env, error] -> Result[Path] {
  let host = (env.get("XSH_HOST") ?? "").trim()

  if host != "" {
    let host_path = fp"${host}"

    if fs.exists(host_path)? {
      return host_path
    }
  }

  if fs.exists(/bin/xsh)? {
    return /bin/xsh
  }

  process.which("xsh")?
}

proc regular_xsh_source(xsh: Path) [fs, error] -> Result[Path] {
  var source = xsh
  var depth = 0

  while depth < 16 {
    let metadata = fs.metadata(source)?

    if metadata.kind != "symlink" {
      return source
    }

    let target = source.readlink()?
    source = if target.display().starts_with("/") { target } else { fp"${source.parent}/${target}" }
    depth += 1
  }

  return Err(PmError.PackageContract(f"${xsh.display()} has too many symlink levels"))
}

proc seed_xsh_multicall(root: Path, xsh: Path) [fs, error] {
  let bin = fp"${root}/bin"
  let multicall = fp"${bin}/xsh-multicall"
  fs.mkdir(bin)?
  fs.remove(multicall, missing_ok: true)?
  fs.install(regular_xsh_source(xsh)?, multicall, 0o755, parents: true, overwrite: true)?

  for name in ["xsh", "xshi", "xsht"] {
    let dest = fp"${bin}/${name}"
    fs.remove(dest, missing_ok: true)?
    fs.symlink(p"xsh-multicall", dest)?
  }
}

proc seed_package_proof_shell(proof_root: Path, xsh: Path) [fs, process, env, error] {
  seed_xsh_multicall(proof_root, xsh)?

  for proof_sh in [fp"${proof_root}/usr/bin/sh", fp"${proof_root}/bin/sh"] {
    fs.mkdir(proof_sh.parent)?
    fs.remove(proof_sh, missing_ok: true)?
    fs.write(proof_sh, seeded_shell_script())?
    fs.chmod(proof_sh, 0o755)?
  }

  let pm_root = pm_source_root()?
  fs.install(fp"${pm_root}/pm.xsh", fp"${proof_root}/usr/lib/pm/pm.xsh", 0o644, parents: true, overwrite: true)?
  fs.remove(fp"${proof_root}/usr/lib/pm/pm", missing_ok: true)?
  let _ = fs.copy_tree(fp"${pm_root}/pm", fp"${proof_root}/usr/lib/pm/pm", parents: true, overwrite: true)?
}

proc seed_chroot_device_paths(root: Path) [fs, error] {
  fs.mkdir(fp"${root}/dev")?
  let dev_null = fp"${root}/dev/null"

  if ! fs.exists(dev_null)? {
    fs.write(dev_null, "")?
    fs.chmod(dev_null, 0o666)?
  }

  let dev_fd = fp"${root}/dev/fd"
  fs.remove(dev_fd, missing_ok: true)?
  fs.symlink(/proc/self/fd, dev_fd)?
}

proc mount_package_proof_devpts(proof_root: Path) [fs, process, error] -> Result[Path] {
  let dev = fp"${proof_root}/dev"
  let pts = fp"${dev}/pts"
  fs.mkdir(pts)?
  fs.remove(fp"${dev}/ptmx", missing_ok: true)?
  fs.symlink(p"pts/ptmx", fp"${dev}/ptmx")?
  let mount = process.which("mount")?
  run $mount "-t" "devpts" "devpts" $pts "-o" "newinstance,ptmxmode=0666,mode=0620" ?
  pts
}

proc unmount_package_proof_devpts(pts: Path) [process] {
  match process.which("umount") {
    Ok(umount) => let _ = run.status $umount $pts
    Err(_) => {}
  }
}

proc verify_package_proof_root(root: Path, name: Str) [fs, error] {
  let db = package_db_path(root, name)

  if ! fs.exists(db)? {
    return Err(PmError.PackageTarball(f"${name} proof root is missing package metadata"))
  }

  let manifest = load_manifest(db)?

  for rel_path in manifest {
    let installed = fp"${root}/${rel_path}"

    match fs.metadata(installed) {
      Ok(_) => {}
      Err(_) => return Err(PmError.PackageTarball(f"${name} proof root is missing ${rel_path.display()}"))
    }
  }
}

pure manifest_installs_service(manifest: List[Path]) -> Bool {
  for rel_path in manifest {
    let entry = rel_path.display()

    if entry.starts_with("usr/lib/xinit/services/") and entry.ends_with(".xsh") {
      return true
    }
  }

  return false
}

# Locate an xinit script to validate service definitions with. Prefers an
# explicit XINIT_HOST override, then an installed /usr/bin/xinit, then PATH.
# Errors with an actionable PackageContract when none is found, since a package
# that ships service.xsh cannot be proven without one.
proc resolve_service_xinit(name: Str) [fs, process, env, error] -> Result[Path] {
  let host = (env.get("XINIT_HOST") ?? "").trim()

  if host != "" {
    let host_path = fp"${host}"

    if fs.exists(host_path)? {
      return host_path
    }
  }

  if fs.exists(/usr/bin/xinit)? {
    return /usr/bin/xinit
  }

  match process.which("xinit") {
    Ok(found) => return found
    Err(_) => {}
  }

  return Err(
    PmError.PackageContract(
      f"${name} ships service.xsh but no xinit was found to validate it; install the xinit package or set XINIT_HOST to an xinit script",
    ),
  )
}

# A package is an xinit service when it ships a service.xsh next to its
# PKGBUILD, mirroring the required proof.xsh. The service definition must be
# installed under /usr/lib/xinit/services/ and is validated with `xinit check`
# during the package proof, so a malformed or undeclared service fails the
# build instead of the running system.
proc verify_service_contract(pkg: Package, manifest: List[Path]) [fs, process, env, error] {
  let service_file = fp"${pkg.dir}/service.xsh"
  let has_service = fs.exists(service_file)?
  let installs_service = manifest_installs_service(manifest)

  if installs_service and ! has_service {
    return Err(
      PmError.PackageContract(
        f"${pkg.name} installs an xinit service under /usr/lib/xinit/services/ but is missing service.xsh",
      ),
    )
  }

  if has_service and ! installs_service {
    return Err(
      PmError.PackageContract(
        f"${pkg.name} defines service.xsh but build() does not install it under /usr/lib/xinit/services/",
      ),
    )
  }

  if ! has_service {
    return
  }

  let xinit = resolve_service_xinit(pkg.name)?
  let xsh = xsh_runner()?
  let scratch_root = fs.tempdir()?
  defer fs.close_root(scratch_root)?
  let scratch = fs.root_path(scratch_root)?
  let out_log = fp"${scratch}/service-check.out"
  let err_log = fp"${scratch}/service-check.err"
  let status = run.status $xsh $xinit "--" check $service_file > $out_log 2> $err_log

  if ! status.ok {
    return Err(
      PmError.PackageContract(
        f"${pkg.name} service.xsh failed xinit check: ${err_log.read_text()?.trim()} ${out_log.read_text()?.trim()}",
      ),
    )
  }

  print f"${pkg.name} service ${out_log.read_text()?.trim()}"
}

proc run_package_proof(
  ctx: PmContext,
  pkg: Package,
  id: Str,
  tarball: Path,
  manifest: List[Path],
  previous: List[BuiltPackage],
  build_log_text: Str,
  build_log: Path,
) [fs, process, env, error] {
  let proof = fp"${pkg.dir}/proof.xsh"

  if ! fs.exists(proof)? {
    return Err(PmError.PackageContract(f"${pkg.name} is missing proof.xsh"))
  }

  verify_service_contract(pkg, manifest)?
  let proof_root = fp"${ctx.work}/${id}-proof-root"
  fs.remove(proof_root, missing_ok: true)?
  fs.mkdir(proof_root)?

  if fs.exists(ctx.root)? {
    fs.copy_tree(ctx.root, proof_root, parents: true, overwrite: true)?
  }

  for item in previous {
    archive.tar_extract(item.tarball, proof_root, 0, "auto", true)?
  }

  let proof_db = package_db_path(proof_root, pkg.name)

  if fs.exists(proof_db)? {
    let old_manifest = load_manifest(proof_db)?
    let _ = fs.remove_manifest(proof_root, old_manifest, missing_ok: true)?
    fs.remove(proof_db, missing_ok: true)?
  }

  let installed_owners = load_installed_owners(proof_root)?

  for rel_path in manifest {
    let key = rel_path.display()

    if ! installed_owners.has(key) {
      fs.remove(fp"${proof_root}/${rel_path}", missing_ok: true)?
    }
  }

  archive.tar_extract(tarball, proof_root, 0, "auto", true)?
  verify_package_proof_root(proof_root, pkg.name)?
  pm_proof.verify_package_elf_dependencies(proof_root, pkg.name)?
  let xsh = xsh_runner()?
  seed_package_proof_shell(proof_root, xsh)?
  seed_chroot_device_paths(proof_root)?
  let build_arch = util.build_arch()?
  let target_arch = util.target_arch()?
  let native_proof = build_arch == target_arch and (env.get("XSH_PM_BUILD_CHROOT") ?? "1") != "0"

  if native_proof {
    # note: not working on macos
    # let proof_devpts = mount_package_proof_devpts(proof_root)?
    # defer unmount_package_proof_devpts(proof_devpts)
    let proof_stage = fp"${proof_root}/var/tmp/pm-proof/${pkg.name}"
    fs.mkdir(proof_stage)?
    fs.install(proof, fp"${proof_stage}/proof.xsh", 0o644, parents: true, overwrite: true)?
    let host_chroot_runner = fp"${pm_source_root()?}/pm/chroot-run.xsh"

    env {
      LAPUTA_ROOT = "/"
      PATH = pm_env.build_path(/, "/bin:/usr/bin")
      XSH_MODULE_PATH = "/usr/lib/pm"
      XSH_LINUX_REAL = "1"
      XSH_PM_ARCH = target_arch
      XSH_PM_BUILD_ARCH = build_arch
      XSH_PM_BUILD_ROOT = "/"
      XSH_PM_PROOF_ROOT = "/"
      XSH_PM_PROOF_HOST_PATH = env.get("PATH") ?? ""
      XSH_PM_TARGET_ARCH = target_arch
      SHELL = "/bin/xshi"
    } {
      run_logged_proof_command(
        xsh,
        [
          xsh.display(),
          host_chroot_runner.display(),
          "--",
          proof_root.display(),
          pkg.name,
          "/bin/xsh",
          f"/var/tmp/pm-proof/${pkg.name}/proof.xsh",
          "--",
          "/",
        ],
        build_log_text,
        build_log,
      )?
    } ?
  } else {
    env {
      PATH = f"${proof_root}/bin:${proof_root}/usr/bin:${env.get("PATH") ?? ""}"
      XSH_MODULE_PATH = env.get("XSH_MODULE_PATH") ?? "/usr/lib/pm"
      XSH_PM_PROOF_ROOT = proof_root.display()
      XSH_PM_PROOF_HOST_PATH = env.get("PATH") ?? ""
      SHELL = fp"${proof_root}/bin/xshi"
    } {
      run_logged_proof_command(
        xsh,
        [xsh.display(), proof.display(), "--", proof_root.display()],
        build_log_text,
        build_log,
      )?
    } ?
  }

  append_build_log_or_print(build_log_text, build_log, f"${pkg.name} proof: ok")?
}
