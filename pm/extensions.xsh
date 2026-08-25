##! PM extension discovery and lifecycle-hook execution.
use types as pm_types

type ScriptCommand = {target: Path, argv: List[Str]}

proc command_for_script(script: Path, argv: List[Str]) [fs, env, error] -> Result[ScriptCommand] {
  if (env.get("XSH_PM_BUILD_CHROOT") ?? "1") != "0" {
    return {target: script, argv}
  }

  let shebang = match fs.read_text(script) {
    Ok(text_value) => text_value.split("\n").get(0, ""),
    Err(_) => "",
  }

  if shebang != "#!/bin/xsh" {
    return {target: script, argv}
  }

  let host = (env.get("XSH_HOST") ?? "").trim()

  if host == "" {
    return {target: script, argv}
  }

  let target = fp"${host}"

  if ! fs.exists(target)? {
    return {target: script, argv}
  }

  var host_argv = [target.display(), script.display(), "--"]
  var index = 1

  while index < argv.len() {
    host_argv = host_argv.push(argv[index])
    index += 1
  }

  {target, argv: host_argv}
}

## Reads the one-line summary embedded in an extension executable.
export proc read_extension_summary(candidate: Path) [fs] -> Result[Str] {
  match fs.read_text(candidate) {
    Ok(text_value) => {
      let lines = text_value.lines().collect()

      if lines.len() > 1 {
        let summary = lines[1].trim()

        if summary.starts_with("#") {
          return summary.replace("#", "").trim()
        }
      }
    }
    Err(_) => {}
  }

  ""
}

## Yields executable PM extensions found on PATH in stable order.
export stream extension_candidates() [fs, env, error] -> Stream[pm_types.Extension] {
  var seen: Map[Bool] = {}
  let path_entries = env.path_entries("PATH")?

  for entry in path_entries {
    continue when entry.empty
    let dir = entry.path

    if fs.exists(dir)? {
      let dir_metadata = fs.metadata(dir)?

      if dir_metadata.kind == "dir" {
        let entries = fs.children(dir)
          |> where .name.starts_with("pm-") and .executable
          |> sort-by .name

        for child_entry in entries {
          let action = child_entry.name.replace("pm-", "")

          if ! set.has(seen, action) {
            let summary = read_extension_summary(child_entry.path)?
            yield {name: action, path: child_entry.path, summary}
            seen = set.add(seen, action)
          }
        }
      }
    }
  }
}

## Discovers all available PM extensions.
export proc discover_extensions() [fs, env, error] -> Result[List[pm_types.Extension]] {
  extension_candidates() |> sort-by .name
}

## Resolves one PM extension action by name.
export proc find_extension(action: Str) [fs, env, error] -> Result[pm_types.Extension] {
  for extension in extension_candidates() {
    if extension.name == action {
      return extension
    }
  }

  return Err(pm_types.PmError.Usage(f"usage: pm ACTION ROOT WORK OUT [ARGS...]; unknown command ${action}"))
}

## Exported PM declaration `print_extension_help`.
export proc print_extension_help() [fs, env, error] {
  let extensions = discover_extensions()?

  if extensions.len() == 0 {
    print extension none
    return
  }

  for extension in extensions {
    print "extension" ${extension.name} ${extension.summary}
  }
}

## Exported PM declaration `run_extension_process`.
export proc run_extension_process(
  action: Str,
  executable: Path,
  argv: List[Str],
  arg_text: Str,
  ctx: pm_types.PmContext,
) [fs, process, env, error] {
  let command = command_for_script(executable, argv)?

  let command_plan = process.command_argv(
    command.target,
    command.argv,
    fs.cwd()?,
    {
      XSH_PM_ROOT: ctx.root.display(),
      XSH_PM_WORK: ctx.work.display(),
      XSH_PM_OUT: ctx.out.display(),
      XSH_PM_ACTION: action,
      XSH_PM_ARGS: arg_text,
    },
  )

  let status = process.run(command_plan)?

  if ! status.ok {
    return Err(pm_types.PmError.ExtensionFailed(f"${action} failed"))
  }
}

## Invokes a named extension with the current PM context.
export proc invoke_extension(action: Str, ctx: pm_types.PmContext, raw: List[Str]) [fs, process, env, error] {
  let extension = find_extension(action)?
  var argv = [extension.path.name]

  for item in raw {
    argv = argv.push(item)
  }

  run_extension_process(action, extension.path, argv, raw.join("\n"), ctx)?
}

proc hook_paths() [env, error] -> Result[List[Path]] {
  var hook_var = ""

  if (env.get("XSH_PM_HOOKS") ?? "").trim() != "" {
    hook_var = "XSH_PM_HOOKS"
  } else if (env.get("LAPUTA_HOOK") ?? "").trim() != "" {
    hook_var = "LAPUTA_HOOK"
  }

  var paths = []

  if hook_var != "" {
    for entry in env.path_entries(hook_var)? {
      let trimmed = entry.raw.trim()

      if trimmed != "" {
        paths = paths.push(fp"${trimmed}")
      }
    }
  }

  paths
}

## Exported PM declaration `load_hook_paths`.
export proc load_hook_paths() [env, error] -> Result[List[Path]] {
  hook_paths()
}

## Runs executable lifecycle hooks for a package operation.
export proc run_lifecycle_hooks(
  hook_name: Str,
  pkg_name: Str,
  ctx: pm_types.PmContext,
  extra: Str,
) [fs, process, env, error] {
  let hooks = hook_paths()?

  for hook in hooks {
    if ! fs.exists(hook)? {
      return Err(pm_types.PmError.LifecycleHook(f"${hook_name} hook not found: ${hook.display()}"))
    }

    if ! fs.executable(hook)? {
      return Err(pm_types.PmError.LifecycleHook(f"${hook_name} hook is not executable: ${hook.display()}"))
    }

    let argv = [hook.name, hook_name, pkg_name, extra]
    let command = command_for_script(hook, argv)?

    let status = process.run(
      process.command_argv(
        command.target,
        command.argv,
        fs.cwd()?,
        {
          XSH_PM_ROOT: ctx.root.display(),
          XSH_PM_WORK: ctx.work.display(),
          XSH_PM_OUT: ctx.out.display(),
          XSH_PM_ACTION: ctx.command,
          XSH_PM_HOOK: hook_name,
          XSH_PM_PACKAGE: pkg_name,
          XSH_PM_EXTRA: extra,
          XSH_PM_ARGS: argv.join("\n"),
        },
      ),
    )?

    if ! status.ok {
      return Err(pm_types.PmError.LifecycleHook(f"${hook_name} hook failed: ${hook.display()}"))
    }
  }
}
