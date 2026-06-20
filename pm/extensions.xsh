use types

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

export stream extension_candidates() [fs, env, error] -> Stream[Extension] {
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

export proc discover_extensions() [fs, env, error] -> Result[List[Extension]] {
  extension_candidates() |> sort-by .name
}

export proc find_extension(action: Str) [fs, env, error] -> Result[Extension] {
  for extension in extension_candidates() {
    if extension.name == action {
      return extension
    }
  }

  return Err(PmError.Usage(f"usage: pm ACTION ROOT WORK OUT [ARGS...]; unknown command ${action}"))
}

export proc print_extension_help() [fs, env, error] {
  let extensions = discover_extensions()?

  if extensions.len() == 0 {
    print extension none
    return
  }

  for extension in extensions {
    print $extension ${extension.name} ${extension.summary}
  }
}

export proc run_extension_process(
  action: Str,
  executable: Path,
  argv: List[Str],
  arg_text: Str,
  ctx: PmContext,
) [fs, process, error] {
  let command_plan = process.command_argv(
    executable,
    argv,
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
    return Err(PmError.ExtensionFailed(f"${action} failed"))
  }
}

export proc invoke_extension(action: Str, ctx: PmContext, raw: List[Str]) [fs, process, env, error] {
  let extension = find_extension(action)?
  var argv = [extension.path.name]

  for item in raw {
    argv = argv.push(item)
  }

  run_extension_process(action, extension.path, argv, raw.join("\n"), ctx)?
}

export stream hook_paths() [env, error] -> Stream[Path] {
  var hook_var = ""

  if (env.get("XSH_PM_HOOKS") ?? "").trim() != "" {
    hook_var = "XSH_PM_HOOKS"
  } else if (env.get("LAPUTA_HOOK") ?? "").trim() != "" {
    hook_var = "LAPUTA_HOOK"
  }

  if hook_var == "" {
    return
  }

  for entry in env.path_entries(hook_var)? {
    let trimmed = entry.raw.trim()

    if trimmed != "" {
      yield Path.parse(trimmed)?
    }
  }
}

export proc load_hook_paths() [env, error] -> Result[List[Path]] {
  hook_paths().collect()
}

export proc run_lifecycle_hooks(hook_name: Str, pkg_name: Str, ctx: PmContext, extra: Str) [fs, process, env, error] {
  for hook in hook_paths() {
    if ! fs.exists(hook)? {
      return Err(PmError.LifecycleHook(f"${hook_name} hook not found: ${hook.display()}"))
    }

    if ! fs.executable(hook)? {
      return Err(PmError.LifecycleHook(f"${hook_name} hook is not executable: ${hook.display()}"))
    }

    let argv = [hook.name, hook_name, pkg_name, extra]

    let status = process.run(
      process.command_argv(
        hook,
        argv,
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
      return Err(PmError.LifecycleHook(f"${hook_name} hook failed: ${hook.display()}"))
    }
  }
}
