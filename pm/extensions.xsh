use types

export proc read_extension_summary(candidate: Path) [fs] -> Result[Str] {
  match fs.read_text(candidate) {
    Ok(text_value) => {
      let lines = text_value.lines()

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

export proc discover_extensions() [fs, error] -> Result[List[Extension]] {
  var extensions: List[Extension] = []
  var seen: Map[Bool] = map.empty()
  let path_list = env.PathList.PATH?

  for dir in path_list {
    if fs.exists(dir)? {
      let dir_metadata = fs.metadata(dir)?

      if dir_metadata.kind == "dir" {
        let entries = fs.children(dir)
          |> where .name.starts_with("pm-") and fs.executable(.path)?
          |> sort-by .name

        for entry in entries {
          let action = entry.name.replace("pm-", "")

          if ! seen.get(action, false) {
            let summary = read_extension_summary(entry.path)?
            extensions = extensions.push({name: action, path: entry.path, summary})
            seen = seen.set(action, true)
          }
        }
      }
    }
  }

  let sorted = extensions |> sort-by .name
  sorted
}

export proc find_extension(action: Str) [fs, error] -> Result[Extension] {
  let extensions = discover_extensions()?

  for extension in extensions {
    if extension.name == action {
      return extension
    }
  }

  return Err(PmError.Usage(f"usage: pm ACTION ROOT WORK OUT [ARGS...]; unknown command ${action}"))
}

export proc print_extension_help() [fs, error] {
  let extensions = discover_extensions()?

  if extensions.len() == 0 {
    print extension none
    return
  }

  for extension in extensions {
    print extension ${extension.name} ${extension.summary}
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

export proc invoke_extension(action: Str, ctx: PmContext, raw: List[Str]) [fs, process, error] {
  let extension = find_extension(action)?
  var argv = [extension.path.name]

  for item in raw {
    argv = argv.push(item)
  }

  run_extension_process(
    action,
    extension.path,
    argv,
    raw.join("""
"""),
    ctx,
  )?
}

export proc load_hook_paths() [env] -> Result[List[Str]] {
  var hook_paths: List[Str] = []
  let raw = (env.get("XSH_PM_HOOKS") ?? env.get("LAPUTA_HOOK") ?? "").trim()

  if raw == "" {
    return hook_paths
  }

  for item in raw.split(":") {
    let trimmed = item.trim()

    if trimmed != "" {
      hook_paths = hook_paths.push(trimmed)
    }
  }

  hook_paths
}

export proc run_lifecycle_hooks(hook_name: Str, pkg_name: Str, ctx: PmContext, extra: Str) [fs, process, env, error] {
  let hook_paths = load_hook_paths()?

  for hook_text in hook_paths {
    let hook = Path.parse(hook_text)?

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
          XSH_PM_ARGS: argv.join("""
"""),
        },
      ),
    )?

    if ! status.ok {
      return Err(PmError.LifecycleHook(f"${hook_name} hook failed: ${hook.display()}"))
    }
  }
}
