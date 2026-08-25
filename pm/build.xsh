##! Isolated package payload construction for the immutable plan executor.
use local
use pm.env as pm_env
use recipe
use types
use util

proc pm_source_root() [fs, env, error] -> Result[Path] {
  for entry in (env.get("XSH_MODULE_PATH") ?? "/usr/lib/pm").split(":") {
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

  /usr/lib/pm
}

pure seeded_shell_script() -> Str {
  return r"""#!/bin/xsh
error ShError = Failed(message: Str)

proc build_shell_run_argv(argv: List[Str]) [process, error] {
  if argv.len() == 0 {
    return
  }

  let status = process.run(process.command_argv(argv[0], argv))?

  if ! status.ok {
    let rendered = argv.join(" ")
    Err(ShError.Failed(message: f"command failed: ${rendered}"))?
  }
}

proc build_shell_run_command_list(script: Str) [process, error] {
  for part in script.split("&&") {
    let command = part.trim()
    continue when command == "" or command == ":"
    build_shell_run_argv(process.argv_words(command)?)?
  }
}

proc build_shell_run_xshi(argv: List[Str]) [process, error] {
  let xshi_argv = ["/bin/xshi"].extend(argv)
  let status = process.run(process.command_argv("/bin/xshi", xshi_argv))?

  if ! status.ok {
    Err(ShError.Failed(message: "xshi failed"))?
  }
}

proc main(...argv: List[Str]) [process, error] {
  if argv.len() >= 2 and argv[0] == "-c" {
    build_shell_run_command_list(argv[1])?
  } else {
    build_shell_run_xshi(argv)?
  }
}

main(@args)?
"""
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

  return Err(types.PmError.PackageContract(f"${xsh.display()} has too many symlink levels"))
}

proc direct_xsh_source(xsh: Path, name: Str) [fs, error] -> Result[Path] {
  if name == "xsh" {
    return regular_xsh_source(xsh)
  }

  let sibling = fp"${xsh.parent}/${name}"
  if ! fs.exists(sibling)? {
    return Err(types.PmError.PackageContract(f"missing direct XSH release binary ${sibling}"))
  }

  regular_xsh_source(sibling)
}

proc seed_xsh_runners(root: Path, xsh: Path) [fs, error] {
  let bin = fp"${root}/bin"
  fs.mkdir(bin)?

  for name in ["xsh", "xshi", "xsht"] {
    let source = direct_xsh_source(xsh, name)?
    let dest = fp"${bin}/${name}"
    fs.remove(dest, missing_ok: true)?
    fs.install(source, dest, 0o755, parents: true, overwrite: true)?
  }
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

## Seeds the explicitly selected XSH/PM substrate into an executor-local mutable work root.
## Completed package roots remain immutable; this function never targets a generation root.
export proc seed_executor_substrate(root: Path) [fs, process, env, error] {
  let xsh = xsh_runner()?
  seed_xsh_runners(root, xsh)?

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

## Builds one prepared recipe into a deterministic payload tarball in executor-owned work.
export proc build_prepared_package(pkg_dir: Path, src: Path, dest: Path, tarball: Path) [fs, process, env, error] {
  let packages = local.load_package_dirs([pkg_dir])?
  let pkg = packages[0]
  let makeflags = env.get("MAKEFLAGS") ?? f"-s -j${cpu.count()}"

  env {
    DESTDIR = dest
    LAPUTA_ROOT = env.get("LAPUTA_ROOT") ?? "/"
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
    let runner = fp"${pkg_dir}/run-package-build.xsh"
    let runner_text = """use pm.recipe

proc main(pkg_dir: Path, src: Path, dest: Path) [fs, process, env, error] {
  let pkg = recipe.load_package(pkg_dir)?
  recipe.call_prepare(pkg, src)?
  fs.remove(dest, missing_ok: true)?
  fs.mkdir(dest)?
  recipe.call_build(pkg, src, dest)?
}

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
          pkg_dir.display(),
          src.display(),
          dest.display(),
        ],
      ),
    )?

    if ! status.ok {
      if status.exited() {
        return Err(types.PmError.ExtensionFailed(f"package build for ${pkg.name} exited with status ${status.exit_code()?}"))
      }

      return Err(types.PmError.ExtensionFailed(f"package build for ${pkg.name} was signaled"))
    }
  } ?

  let manifest = fs.walk(dest)
    |> where .kind == "file" or .kind == "symlink"
    |> map { |entry| entry.path.strip_prefix(dest)? }
    |> sort-by .display()

  local.validate_and_strip_package(pkg, dest, manifest)?
  let etcsums = local.collect_etcsums(dest, manifest)?
  local.write_package_db(dest, pkg, manifest, etcsums)?
  let dest_text = dest.display()
  var archive_paths: List[Path] = []

  for entry in fs.walk(dest) {
    var include = entry.kind == "file" or entry.kind == "symlink"

    if entry.kind == "dir" and entry.path.display() != dest_text and local.dir_empty(entry.path)? {
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
