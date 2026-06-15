use kbuild
use pm.make as make

error ScriptError = Failed(kind: Str, message: Str)

export proc build_jobs() [env, error] -> Result[Int] {
  let raw = env.get("XSH_LINUX_KBUILD_JOBS") ?? ""

  if raw != "" {
    let parsed = raw.parse_int()?

    if parsed <= 0 {
      return Err(ScriptError.Failed("linux-kbuild-jobs", "XSH_LINUX_KBUILD_JOBS must be a positive integer"))
    }

    return parsed
  }

  return make.jobs()
}

export proc discover_options_from_env() [env, error] -> Result[kbuild.DiscoverOptions] {
  let every_text = env.get("XSH_LINUX_KBUILD_PROGRESS_EVERY") ?? "100"
  let jobs_text = env.get("XSH_LINUX_KBUILD_DISCOVER_JOBS") ?? ""
  let jobs_count = if jobs_text == "" { build_jobs()? } else { jobs_text.parse_int()? }

  return {
    progress: (env.get("XSH_LINUX_KBUILD_PROGRESS") ?? "") == "1",
    progress_every: every_text.parse_int()?,
    jobs: jobs_count,
  }
}

export proc discover_package_plan(srcarch: Str) [fs, env, error] -> Result[kbuild.KbuildPlan] {
  let config = kbuild.load_config(p".config")?
  return kbuild.discover_plan_with_options(p".", config, srcarch, discover_options_from_env()?)?
}

export proc requested_stop_after() [env, error] -> Result[Str] {
  let requested = env.get("XSH_LINUX_KBUILD_STOP_AFTER") ?? ""

  if requested == "" {
    return ""
  }

  if ! ["prepare", "discover", "plan", "compile", "link"].contains(requested) {
    return Err(
      ScriptError.Failed(
        "linux-kbuild-stop-after",
        f"XSH_LINUX_KBUILD_STOP_AFTER must be prepare, discover, plan, compile, or link; got '${requested}'",
      ),
    )
  }

  return requested
}

export proc stop_after(stage: Str) [env, error] {
  if requested_stop_after()? == stage {
    return Err(ScriptError.Failed("linux-kbuild-stopped", f"stopped after ${stage}"))
  }
}

export proc timing_start(stage: Str) [env] -> Int {
  if (env.get("XSH_LINUX_KBUILD_TIMING") ?? "") == "1" {
    print linux-kbuild-timing-start ${stage}
  }

  return 0
}

export proc timing_done(stage: Str, start: Int) [env] {
  let _ = start

  if (env.get("XSH_LINUX_KBUILD_TIMING") ?? "") == "1" {
    print linux-kbuild-timing-done ${stage}
  }
}

export proc emit_plan_if_enabled(plan: kbuild.KbuildPlan) [fs, env, error] {
  if (env.get("XSH_LINUX_KBUILD_PLAN") ?? "") == "1" {
    kbuild.write_discovered_plan(plan, p".xsh-kbuild-plan.json")?
    print xsh-kbuild-plan ${plan.dirs.len()} dirs ${plan.objects.len()} objects ${plan.unsupported.len()} unsupported
  }
}

export proc emit_kbuild_progress(message: Str) [fs, env, error] {
  if (env.get("XSH_LINUX_KBUILD_PROGRESS") ?? "") == "1" {
    kbuild.write_text_if_changed(
      p".xsh-kbuild-progress",
      f"""${message}
""",
    )?

    print ${message}
  }
}

proc remove_archive_plan_cache() [fs, error] {
  fs.remove(p".xsh-kbuild-archive-plan.json", missing_ok: true)?
  fs.remove(p".xsh-kbuild-archive-plan.json.summary", missing_ok: true)?
  fs.remove(p".xsh-kbuild-archive-plan.fingerprint", missing_ok: true)?
}

proc archive_plan_cache_fingerprint(
  plan: kbuild.KbuildPlan,
  srcarch: Str,
  triple: Str,
  cflags: List[Str],
  includes: List[Str],
) [fs, error] -> Result[Str] {
  return f"""format linux-archive-plan-cache-v1
srcarch ${srcarch}
triple ${triple}
plan
${kbuild.plan_fingerprint(p".", p".config", plan)?}
cflags
${cflags.join("\n")}
includes
${includes.join("\n")}
"""
}

proc archive_plan_fingerprint_matches(path_value: Path, fingerprint: Str) [fs, error] -> Result[Bool] {
  if ! path_value.exists()? {
    return false
  }

  return path_value.read_text()?.trim() == fingerprint.trim()
}

proc write_archive_plan_fingerprint(path_value: Path, fingerprint: Str) [fs, error] {
  kbuild.write_text_if_changed(path_value, f"""${fingerprint}
""")?
}

proc copy_archive_plan_cache(source: Path, dest: Path) [fs, error] {
  if ! source.exists()? {
    return
  }

  fs.install(source, dest, 0o644, parents: true, overwrite: true)?
  let source_summary = kbuild.archive_plan_summary_path(source)

  if source_summary.exists()? {
    fs.install(source_summary, kbuild.archive_plan_summary_path(dest), 0o644, parents: true, overwrite: true)?
  }
}

export proc cached_archive_plan(
  plan: kbuild.KbuildPlan,
  cc: Path,
  srcarch: Str,
  triple: Str,
  cflags: List[Str],
  includes: List[Str],
) [fs, env, error] -> Result[Record] {
  if srcarch != "arm64" and srcarch != "x86" {
    return Err(
      ScriptError.Failed(
        "linux-native-kbuild-unsupported-arch",
        f"native scratch Kbuild final link is only implemented for arm64 and x86; ${srcarch} needs new arch support",
      ),
    )
  }

  let archive_report = p".xsh-kbuild-archive-plan.json"
  let archive_fingerprint = p".xsh-kbuild-archive-plan.fingerprint"
  let stable_cache_dir = Path.parse(env.get("XSH_LINUX_KBUILD_PLAN_CACHE_DIR") ?? "/var/cache/laputa/linux-kbuild")?
  let stable_archive_report = fp"${stable_cache_dir.display()}/linux-${srcarch}.archive-plan.json"
  let stable_archive_fingerprint = fp"${stable_cache_dir.display()}/linux-${srcarch}.archive-plan.fingerprint"
  let fingerprint = archive_plan_cache_fingerprint(plan, srcarch, triple, cflags, includes)?
  let reuse_archive_plan = (env.get("XSH_LINUX_KBUILD_REUSE_ARCHIVE_PLAN") ?? "") == "1"
  let plan_only = requested_stop_after()? == "plan" and (env.get("XSH_LINUX_KBUILD_ONLY") ?? "") == ""

  if reuse_archive_plan and (env.get("XSH_LINUX_KBUILD_FORCE_ARCHIVES") ?? "") != "1" {
    if archive_report.exists()? and archive_plan_fingerprint_matches(archive_fingerprint, fingerprint)? {
      if plan_only {
        match kbuild.read_archive_plan_summary(kbuild.archive_plan_summary_path(archive_report)) {
          Ok(archive_plan) => {
            emit_kbuild_progress(f"xsh-kbuild-archive-plan-summary-cache ${archive_plan.task_count} tasks ${archive_plan.archives.len()} archives ${archive_plan.link_inputs.len()} link-inputs")?
            return archive_plan
          }
          Err(ScriptError.Failed {kind: kind, message: _}) => emit_kbuild_progress(f"xsh-kbuild-archive-plan-summary-cache miss ${kind}")?
        }
      }

      match kbuild.read_archive_plan_report(archive_report) {
        Ok(archive_plan) => {
          emit_kbuild_progress(f"xsh-kbuild-archive-plan-cache ${archive_plan.tasks.len()} tasks ${archive_plan.archives.len()} archives ${archive_plan.link_inputs.len()} link-inputs")?

          if plan_only {
            kbuild.write_archive_plan_summary(archive_plan, kbuild.archive_plan_summary_path(archive_report))?
          }

          return archive_plan
        }
        Err(ScriptError.Failed {kind: kind, message: _}) => emit_kbuild_progress(f"xsh-kbuild-archive-plan-cache miss ${kind}")?
      }
    }

    if stable_archive_report.exists()? and archive_plan_fingerprint_matches(stable_archive_fingerprint, fingerprint)? {
      if plan_only {
        match kbuild.read_archive_plan_summary(kbuild.archive_plan_summary_path(stable_archive_report)) {
          Ok(archive_plan) => {
            emit_kbuild_progress(f"xsh-kbuild-archive-plan-stable-summary-cache ${archive_plan.task_count} tasks ${archive_plan.archives.len()} archives ${archive_plan.link_inputs.len()} link-inputs")?
            copy_archive_plan_cache(stable_archive_report, archive_report)?
            write_archive_plan_fingerprint(archive_fingerprint, fingerprint)?
            return archive_plan
          }
          Err(ScriptError.Failed {kind: kind, message: _}) => emit_kbuild_progress(f"xsh-kbuild-archive-plan-stable-summary-cache miss ${kind}")?
        }
      }

      match kbuild.read_archive_plan_report(stable_archive_report) {
        Ok(archive_plan) => {
          emit_kbuild_progress(f"xsh-kbuild-archive-plan-stable-cache ${archive_plan.tasks.len()} tasks ${archive_plan.archives.len()} archives ${archive_plan.link_inputs.len()} link-inputs")?
          copy_archive_plan_cache(stable_archive_report, archive_report)?
          write_archive_plan_fingerprint(archive_fingerprint, fingerprint)?
          return archive_plan
        }
        Err(ScriptError.Failed {kind: kind, message: _}) => emit_kbuild_progress(f"xsh-kbuild-archive-plan-stable-cache miss ${kind}")?
      }
    }
  }

  emit_kbuild_progress(f"xsh-kbuild-archive-plan-start ${plan.dirs.len()} dirs ${plan.objects.len()} objects ${plan.composites.len()} composites")?

  let archive_plan = kbuild.plan_builtin_archives(plan, cc, triple, cflags, [], includes)?
  kbuild.write_archive_plan_report(archive_plan, archive_report)?
  write_archive_plan_fingerprint(archive_fingerprint, fingerprint)?
  stable_cache_dir.mkdir()?
  copy_archive_plan_cache(archive_report, stable_archive_report)?
  write_archive_plan_fingerprint(stable_archive_fingerprint, fingerprint)?

  emit_kbuild_progress(f"xsh-kbuild-archive-plan ${archive_plan.tasks.len()} tasks ${archive_plan.archives.len()} archives ${archive_plan.link_inputs.len()} link-inputs ${archive_plan.generated_objects.len()} generated ${archive_plan.missing_sources.len()} missing")?

  return archive_plan
}


export proc cached_package_plan(srcarch: Str) [fs, env, error] -> Result[kbuild.KbuildPlan] {
  let config = kbuild.load_config(p".config")?
  let explicit_inline = env.get("XSH_LINUX_KBUILD_USE_PLAN_TEXT_INLINE") ?? ""
  let explicit_text = env.get("XSH_LINUX_KBUILD_USE_PLAN_TEXT") ?? ""
  let explicit = env.get("XSH_LINUX_KBUILD_USE_PLAN") ?? ""

  if explicit_inline != "" {
    emit_kbuild_progress("xsh-kbuild-plan-cache explicit-inline-read")?
    let plan = kbuild.parse_discovered_plan_text(explicit_inline)?
    print xsh-kbuild-plan-cache explicit-inline ${plan.dirs.len()} dirs ${plan.objects.len()} objects ${plan.composites.len()} composites
    return plan
  }

  if explicit_text != "" {
    emit_kbuild_progress(f"xsh-kbuild-plan-cache explicit-text-read ${explicit_text}")?
    let plan = kbuild.read_discovered_plan_text(Path.parse(explicit_text)?)?
    print xsh-kbuild-plan-cache explicit-text ${explicit_text} ${plan.dirs.len()} dirs ${plan.objects.len()} objects ${plan.composites.len()} composites
    return plan
  }

  if explicit != "" {
    emit_kbuild_progress(f"xsh-kbuild-plan-cache explicit-read ${explicit}")?
    let plan = kbuild.read_discovered_plan(Path.parse(explicit)?)?
    print xsh-kbuild-plan-cache explicit ${explicit} ${plan.dirs.len()} dirs ${plan.objects.len()} objects ${plan.composites.len()} composites
    return plan
  }

  let force_discover = (env.get("XSH_LINUX_KBUILD_FORCE_DISCOVER") ?? "") == "1"
  let plan_path = p".xsh-kbuild-plan.json"
  let fingerprint_path = p".xsh-kbuild-plan.fingerprint"
  let stable_cache_dir = Path.parse(env.get("XSH_LINUX_KBUILD_PLAN_CACHE_DIR") ?? "/var/cache/laputa/linux-kbuild")?
  let stable_plan_path = fp"${stable_cache_dir.display()}/linux-${srcarch}.plan.json"
  let stable_fingerprint_path = fp"${stable_cache_dir.display()}/linux-${srcarch}.plan.fingerprint"

  if force_discover {
    emit_kbuild_progress("xsh-kbuild-plan-cache force-discover")?
  }

  if ! force_discover and plan_path.exists()? and fingerprint_path.exists()? {
    emit_kbuild_progress("xsh-kbuild-plan-cache read")?
    let plan = kbuild.read_discovered_plan(plan_path)?
    emit_kbuild_progress(f"xsh-kbuild-plan-cache fingerprint ${plan.dirs.len()} dirs ${plan.objects.len()} objects")?

    if (env.get("XSH_LINUX_KBUILD_TRUST_PLAN_CACHE") ?? "") == "1" {
      print xsh-kbuild-plan-cache trusted ${plan.dirs.len()} dirs ${plan.objects.len()} objects ${plan.composites.len()} composites
      return plan
    }

    let fingerprint = kbuild.plan_fingerprint(p".", p".config", plan)?

    if fingerprint_path.read_text()?.trim() == fingerprint.trim() {
      print xsh-kbuild-plan-cache hit ${plan.dirs.len()} dirs ${plan.objects.len()} objects ${plan.composites.len()} composites
      return plan
    }

    if stable_plan_path.exists()? and stable_fingerprint_path.exists()? {
      emit_kbuild_progress("xsh-kbuild-plan-cache stale-stable-read")?
      let stable_plan = kbuild.read_discovered_plan(stable_plan_path)?
      let stable_fingerprint = kbuild.plan_fingerprint(p".", p".config", stable_plan)?

      if stable_fingerprint_path.read_text()?.trim() == stable_fingerprint.trim() {
        kbuild.write_discovered_plan(stable_plan, plan_path)?

        kbuild.write_text_if_changed(
          fingerprint_path,
          f"""${stable_fingerprint}
""",
        )?

        print xsh-kbuild-plan-cache stale-stable-hit ${stable_plan.dirs.len()} dirs ${stable_plan.objects.len()} objects ${stable_plan.composites.len()} composites
        return stable_plan
      }
    }

    if srcarch == "x86" {
      emit_kbuild_progress("xsh-kbuild-plan-cache targeted-repair")?
      let repaired = kbuild.refresh_x86_kernel_config_objects(config, plan)?
      kbuild.write_discovered_plan(repaired, plan_path)?
      remove_archive_plan_cache()?
      let repaired_fingerprint = kbuild.plan_fingerprint(p".", p".config", repaired)?

      kbuild.write_text_if_changed(
        fingerprint_path,
        f"""${repaired_fingerprint}
""",
      )?

      fs.mkdir(stable_cache_dir)?
      kbuild.write_discovered_plan(repaired, stable_plan_path)?

      kbuild.write_text_if_changed(
        stable_fingerprint_path,
        f"""${repaired_fingerprint}
""",
      )?

      print xsh-kbuild-plan-cache targeted-repaired ${repaired.dirs.len()} dirs ${repaired.objects.len()} objects ${repaired.composites.len()} composites
      return repaired
    }

    if srcarch == "arm64" {
      emit_kbuild_progress("xsh-kbuild-plan-cache targeted-repair")?
      let repaired = kbuild.refresh_arm64_kernel_config_objects(config, plan)?
      kbuild.write_discovered_plan(repaired, plan_path)?
      remove_archive_plan_cache()?
      let repaired_fingerprint = kbuild.plan_fingerprint(p".", p".config", repaired)?

      kbuild.write_text_if_changed(
        fingerprint_path,
        f"""${repaired_fingerprint}
""",
      )?

      fs.mkdir(stable_cache_dir)?
      kbuild.write_discovered_plan(repaired, stable_plan_path)?

      kbuild.write_text_if_changed(
        stable_fingerprint_path,
        f"""${repaired_fingerprint}
""",
      )?

      print xsh-kbuild-plan-cache targeted-repaired ${repaired.dirs.len()} dirs ${repaired.objects.len()} objects ${repaired.composites.len()} composites
      return repaired
    }

    emit_kbuild_progress("xsh-kbuild-plan-cache stale")?
  }

  if ! force_discover and stable_plan_path.exists()? and stable_fingerprint_path.exists()? {
    emit_kbuild_progress("xsh-kbuild-plan-cache stable-read")?
    let stable_plan = kbuild.read_discovered_plan(stable_plan_path)?
    let stable_fingerprint = kbuild.plan_fingerprint(p".", p".config", stable_plan)?

    if stable_fingerprint_path.read_text()?.trim() == stable_fingerprint.trim() {
      kbuild.write_discovered_plan(stable_plan, plan_path)?

      kbuild.write_text_if_changed(
        fingerprint_path,
        f"""${stable_fingerprint}
""",
      )?

      print xsh-kbuild-plan-cache stable-hit ${stable_plan.dirs.len()} dirs ${stable_plan.objects.len()} objects ${stable_plan.composites.len()} composites
      return stable_plan
    }

    if srcarch == "x86" {
      emit_kbuild_progress("xsh-kbuild-plan-cache stable-targeted-repair")?
      let repaired = kbuild.refresh_x86_kernel_config_objects(config, stable_plan)?
      kbuild.write_discovered_plan(repaired, plan_path)?
      remove_archive_plan_cache()?
      let repaired_fingerprint = kbuild.plan_fingerprint(p".", p".config", repaired)?

      kbuild.write_text_if_changed(
        fingerprint_path,
        f"""${repaired_fingerprint}
""",
      )?

      fs.mkdir(stable_cache_dir)?
      kbuild.write_discovered_plan(repaired, stable_plan_path)?

      kbuild.write_text_if_changed(
        stable_fingerprint_path,
        f"""${repaired_fingerprint}
""",
      )?

      print xsh-kbuild-plan-cache stable-targeted-repaired ${repaired.dirs.len()} dirs ${repaired.objects.len()} objects ${repaired.composites.len()} composites
      return repaired
    }

    if srcarch == "arm64" {
      emit_kbuild_progress("xsh-kbuild-plan-cache stable-targeted-repair")?
      let repaired = kbuild.refresh_arm64_kernel_config_objects(config, stable_plan)?
      kbuild.write_discovered_plan(repaired, plan_path)?
      remove_archive_plan_cache()?
      let repaired_fingerprint = kbuild.plan_fingerprint(p".", p".config", repaired)?

      kbuild.write_text_if_changed(
        fingerprint_path,
        f"""${repaired_fingerprint}
""",
      )?

      fs.mkdir(stable_cache_dir)?
      kbuild.write_discovered_plan(repaired, stable_plan_path)?

      kbuild.write_text_if_changed(
        stable_fingerprint_path,
        f"""${repaired_fingerprint}
""",
      )?

      print xsh-kbuild-plan-cache stable-targeted-repaired ${repaired.dirs.len()} dirs ${repaired.objects.len()} objects ${repaired.composites.len()} composites
      return repaired
    }

    emit_kbuild_progress("xsh-kbuild-plan-cache stable-miss")?
  }

  emit_kbuild_progress("xsh-kbuild-plan discover-start")?
  let plan = discover_package_plan(srcarch)?
  emit_kbuild_progress(f"xsh-kbuild-plan write ${plan.dirs.len()} dirs ${plan.objects.len()} objects")?
  kbuild.write_discovered_plan(plan, plan_path)?
  remove_archive_plan_cache()?
  emit_kbuild_progress("xsh-kbuild-plan fingerprint")?
  let fingerprint = kbuild.plan_fingerprint(p".", p".config", plan)?

  kbuild.write_text_if_changed(
    fingerprint_path,
    f"""${fingerprint}
""",
  )?

  fs.mkdir(stable_cache_dir)?
  kbuild.write_discovered_plan(plan, stable_plan_path)?

  kbuild.write_text_if_changed(
    stable_fingerprint_path,
    f"""${fingerprint}
""",
  )?

  emit_plan_if_enabled(plan)?
  return plan
}

export proc add_extra_objects_from_env(plan: kbuild.KbuildPlan) [env, error] -> Result[kbuild.KbuildPlan] {
  let raw = (env.get("XSH_LINUX_KBUILD_EXTRA_OBJECTS") ?? "").replace(",", " ")
  var objects = [Path.parse(item)? for item in raw.words()]
  return kbuild.add_plan_objects(plan, objects)
}

proc parse_kbuild_only_outputs(raw: Str) [error] -> Result[List[Path]] {
  var outputs: List[Path] = []

  for item in raw.split(",") {
    let trimmed = item.trim()

    if trimmed != "" {
      outputs = outputs.push(Path.parse(trimmed)?)
    }
  }

  if outputs.len() == 0 {
    return Err(
      ScriptError.Failed(
        "linux-native-kbuild-target-empty",
        "XSH_LINUX_KBUILD_ONLY must name at least one archive-plan output",
      ),
    )
  }

  return outputs
}

export proc run_targeted_kbuild_outputs(archive_plan: Record, only: Str) [fs, process, env, error] {
  let outputs = parse_kbuild_only_outputs(only)?
  let jobs_count = build_jobs()?
  let selected = kbuild.select_archive_tasks_outputs(archive_plan.tasks, outputs)?
  print linux-native-kbuild-target-plan ${selected.len()} tasks ${outputs.len()} outputs

  if requested_stop_after()? == "plan" {
    kbuild.write_archive_plan_report(archive_plan, p".xsh-kbuild-archive-plan.json")?
    stop_after("plan")?
  }

  make.run_tasks(selected, jobs_count)?
  stop_after("compile")?

  return Err(
    ScriptError.Failed(
      "linux-native-kbuild-target-complete",
      f"native scratch Kbuild ran ${outputs.len()} requested target(s); continue with the next targeted object batch or the full archive graph",
    ),
  )
}

export proc require_valid_archive_plan(archive_plan: Record) [error] {
  if archive_plan.has("duplicate_outputs") {
    let duplicates: List[Path] = archive_plan.duplicate_outputs

    if duplicates.len() > 0 {
      return Err(
        ScriptError.Failed(
          "linux-native-kbuild-duplicate-output",
          "archive plan has duplicate output",
        ),
      )
    }
  }

  var outputs: Map[Bool] = map.empty()

  for task in archive_plan.tasks {
    for output in task.outputs {
      let key = output.display()
      continue when key == ""

      if outputs.get(key, false) {
        return Err(
          ScriptError.Failed(
            "linux-native-kbuild-duplicate-output",
            "archive plan has duplicate output",
          ),
        )
      }

      outputs[key] = true
    }
  }
}

export proc require_complete_x86_archive_plan(archive_plan: Record) [error] {
  require_valid_archive_plan(archive_plan)?
  if archive_plan.generated_objects.len() > 0 {
    return Err(
      ScriptError.Failed(
        "linux-native-kbuild-generated-incomplete",
        f"x86 full package build still has ${archive_plan.generated_objects.len()} generated object(s); generate or exclude them before linking",
      ),
    )
  }

  if archive_plan.missing_sources.len() > 0 {
    return Err(
      ScriptError.Failed(
        "linux-native-kbuild-missing-sources",
        f"x86 full package build still has ${archive_plan.missing_sources.len()} selected object(s) without direct sources; restore/generate/exclude them before linking",
      ),
    )
  }
}

export proc native_tool(name: Str) [fs, process, env, error] -> Result[Path] {
  let build_root = env.get("XSH_PM_BUILD_ROOT") ?? ""

  if build_root != "" {
    let tool = Path.parse(f"${build_root}/usr/bin/${name}")?

    if fs.exists(tool)? {
      return tool
    }
  }

  return process.which(name)?
}


export proc run_native_command(argv: List[Str]) [process, env, error] {
  let build_root = env.get("XSH_PM_BUILD_ROOT") ?? ""
  let command = if build_root != "" {
    process.command_argv(
      argv[0],
      argv,
      env: {PATH: f"${build_root}/usr/bin:${env.get("PATH") ?? ""}"},
    )
  } else {
    process.command_argv(argv[0], argv)
  }

  let status = process.run(command)?

  if ! status.ok {
    return Err(ScriptError.Failed("linux-native-kbuild-command", f"command failed: ${argv.join(" ")}"))
  }
}

export proc write_default_builtin_initramfs(cc: Path) [fs, process, env, error] {
  # Keep Linux's default built-in cpio, not a userspace initramfs. With
  # CONFIG_INITRAMFS_SOURCE="", upstream kbuild generates usr/default_cpio_list:
  # /dev, /dev/console, and /root. Those entries are enough for the kernel's
  # no-initramfs block-root path to create /dev/root before mounting the real
  # ext4 root, where xinit then runs as /init.
  #
  # The XSH native Kbuild path does not run usr/Makefile, so we must explicitly
  # generate the same usr/initramfs_inc_data payload here. Writing an empty file
  # regresses direct block-root boot with "Failed to create /dev/root".
  fs.mkdir(p".xsh-kbuild/host")?
  let gen = p".xsh-kbuild/host/gen_init_cpio"
  run_native_command([cc.display(), "-O2", "-o", gen.display(), "usr/gen_init_cpio.c"])?
  let output = run.capture --bytes $gen "usr/default_cpio_list" ?

  if ! output.status.ok {
    return Err(ScriptError.Failed("linux-initramfs-default-cpio", "gen_init_cpio failed"))
  }

  fs.write(p"usr/initramfs_inc_data", output.stdout)?
}
