error ChrootRunError = Failed(message: Str)

proc main(root: Path, package_name: Str, ...argv: List[Str]) [fs, process, env, error] {
  if argv.len() == 0 {
    return Err(ChrootRunError.Failed("missing command"))?
  }

  print f"building ${package_name}"

  linux.chroot(root)?
  let root_dir = /
  let _ = root_dir

  cd root_dir {
    let target = Path.parse(argv[0])?

    env {
      LAPUTA_ROOT = env.get("LAPUTA_ROOT") ?? ""
      MAKEFLAGS = env.get("MAKEFLAGS") ?? ""
      PATH = env.get("PATH") ?? ""
      XSH_MODULE_PATH = env.get("XSH_MODULE_PATH") ?? ""
      XSH_LINUX_REAL = env.get("XSH_LINUX_REAL") ?? ""
      XSH_LINUX_KBUILD_DISCOVER_JOBS = env.get("XSH_LINUX_KBUILD_DISCOVER_JOBS") ?? ""
      XSH_LINUX_KBUILD_FORCE_ARCHIVES = env.get("XSH_LINUX_KBUILD_FORCE_ARCHIVES") ?? ""
      XSH_LINUX_KBUILD_JOBS = env.get("XSH_LINUX_KBUILD_JOBS") ?? ""
      XSH_LINUX_KBUILD_ONLY = env.get("XSH_LINUX_KBUILD_ONLY") ?? ""
      XSH_LINUX_KBUILD_PLAN = env.get("XSH_LINUX_KBUILD_PLAN") ?? ""
      XSH_LINUX_KBUILD_PROGRESS = env.get("XSH_LINUX_KBUILD_PROGRESS") ?? ""
      XSH_LINUX_KBUILD_PROGRESS_EVERY = env.get("XSH_LINUX_KBUILD_PROGRESS_EVERY") ?? ""
      XSH_LINUX_KBUILD_REUSE_ARCHIVE_PLAN = env.get("XSH_LINUX_KBUILD_REUSE_ARCHIVE_PLAN") ?? ""
      XSH_LINUX_KBUILD_REUSE_ARCHIVES = env.get("XSH_LINUX_KBUILD_REUSE_ARCHIVES") ?? ""
      XSH_LINUX_KBUILD_STOP_AFTER = env.get("XSH_LINUX_KBUILD_STOP_AFTER") ?? ""
      XSH_LINUX_KBUILD_TIMING = env.get("XSH_LINUX_KBUILD_TIMING") ?? ""
      XSH_LINUX_KBUILD_TRUST_PLAN_CACHE = env.get("XSH_LINUX_KBUILD_TRUST_PLAN_CACHE") ?? ""
      XSH_LINUX_KBUILD_USE_PLAN = env.get("XSH_LINUX_KBUILD_USE_PLAN") ?? ""
      XSH_LINUX_KBUILD_USE_PLAN_TEXT = env.get("XSH_LINUX_KBUILD_USE_PLAN_TEXT") ?? ""
      XSH_LINUX_KBUILD_USE_PLAN_TEXT_INLINE = env.get("XSH_LINUX_KBUILD_USE_PLAN_TEXT_INLINE") ?? ""
      XSH_PM_ARCH = env.get("XSH_PM_ARCH") ?? ""
      XSH_PM_BUILD_ARCH = env.get("XSH_PM_BUILD_ARCH") ?? ""
      XSH_PM_BUILD_ROOT = env.get("XSH_PM_BUILD_ROOT") ?? ""
      XSH_PM_PROOF_HOST_PATH = env.get("XSH_PM_PROOF_HOST_PATH") ?? ""
      XSH_PM_PROOF_ROOT = env.get("XSH_PM_PROOF_ROOT") ?? ""
      XSH_PM_TARGET_ARCH = env.get("XSH_PM_TARGET_ARCH") ?? ""
      XSH_PM_IN_CHROOT = env.get("XSH_PM_IN_CHROOT") ?? ""
      SHELL = env.get("SHELL") ?? ""
    } {
      let status = process.run(process.command_argv(target, argv, /))?

      if status.ok {
        return
      }

      if status.exited() {
        abort(status.exit_code()?)
      }

      return Err(ChrootRunError.Failed(f"${package_name}: ${argv[0]} was signaled"))?
    } ?
  } ?
}

main(@args)?
