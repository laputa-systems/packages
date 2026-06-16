export error MakeError = InvalidJobs(message: Str) : InvalidData | InvalidTask(message: Str) : InvalidData | DuplicateTask(message: Str) : Conflict | DuplicateOutput(message: Str) : Conflict | MissingDependency(message: Str) : Dependency | DependencyCycle(message: Str) : Dependency | CommandFailed(message: Str) : ProcessFailure

export type MakeTask = {
  name: Str,
  outputs: List[Path],
  inputs: List[Path],
  deps: List[Str],
  argv: List[Str],
  cwd: Path,
  env: Record,
  depfile: Path,
  stamp: Path,
}

pure empty_path() -> Path {
  return p""
}

pure empty_strings() -> List[Str] {
  let empty: List[Str] = []
  return empty
}

pure empty_records() -> List[Record] {
  let empty: List[Record] = []
  return empty
}

pure has_path(path_value: Path) -> Bool {
  return path_value.display() != ""
}

pure stamp_path(out: Path) -> Path {
  return fp"${out}.cmd"
}

pure depfile_path(out: Path) -> Path {
  return fp"${out}.d"
}

pure path_args(paths: List[Path]) -> List[Str] {
  var path_args_out = [path_value.display() for path_value in paths]
  return path_args_out
}

pure all_deps_done(deps: List[Str], done: Map[Bool]) -> Bool {
  for dep in deps {
    if ! done.get(dep, false) {
      return false
    }
  }

  return true
}

pure parse_jobs(value: Str, source: Str) -> Result[Int] {
  let parsed = value.parse_int()?

  if parsed <= 0 {
    return Err(MakeError.InvalidJobs(message: f"${source} must be a positive integer"))
  }

  return parsed
}

pure makeflags_jobs(flags: Str) -> Result[Int] {
  let words = flags.words()
  var index = 0

  while index < words.len() {
    let word = words[index]

    if word.starts_with("-j") and word.count_chars() > 2 {
      return parse_jobs(word.replace("-j", ""), "MAKEFLAGS -j")?
    }

    if word == "-j" or word == "--jobs" {
      if index + 1 >= words.len() {
        return Err(MakeError.InvalidJobs(message: f"MAKEFLAGS ${word} requires a job count"))
      }

      return parse_jobs(words[index + 1], f"MAKEFLAGS ${word}")?
    }

    if word.starts_with("--jobs=") {
      return parse_jobs(word.replace("--jobs=", ""), "MAKEFLAGS --jobs")?
    }

    index += 1
  }

  return cpu.count()
}

export proc jobs() [env, error] -> Result[Int] {
  let value = env.get("MAKEFLAGS") ?? ""

  if value == "" {
    return cpu.count()
  }

  return makeflags_jobs(value)?
}

pure normalize_cross_arch(arch: Str) -> Str {
  if arch == "arm64" {
    return "aarch64"
  }

  if arch == "amd64" {
    return "x86_64"
  }

  arch
}

proc env_value(name: Str) [env] -> Str {
  return (env.get(name) ?? "").trim()
}

proc native_cross_target_arch() [env] -> Str {
  var target = env_value("XSH_PM_TARGET_ARCH")

  if target == "" {
    target = env_value("XSH_PM_ARCH")
  }

  return normalize_cross_arch(target)
}

proc native_cross_active() [env] -> Bool {
  let target = native_cross_target_arch()
  let build = normalize_cross_arch(env_value("XSH_PM_BUILD_ARCH"))

  return target != "" and build != "" and target != build and env_value("LAPUTA_ROOT") != "" and env_value(
    "XSH_PM_BUILD_ROOT",
  ) != ""
}

proc task_disables_native_cross(task_env: Record) [error] -> Result[Bool] {
  if ! task_env.has("XSH_MAKE_NATIVE_CROSS") {
    return false
  }

  let value: Str = task_env.get("XSH_MAKE_NATIVE_CROSS")?
  return value == "0"
}

pure compiler_command_name(command: Str) -> Str {
  let parts = command.split("/")
  return parts[parts.len() - 1]
}

pure is_c_compiler_command(command: Str) -> Bool {
  let name = compiler_command_name(command)
  return name == "cc" or name == "clang" or name == "clang-22"
}

pure is_cxx_compiler_command(command: Str) -> Bool {
  let name = compiler_command_name(command)
  return name == "c++" or name == "clang++"
}

pure is_llvm_tool_command(command: Str) -> Bool {
  let name = compiler_command_name(command)
  return name == "ld.lld" or name == "lld" or name.starts_with("llvm-")
}

pure is_compile_only_argv(argv: List[Str]) -> Bool {
  for arg in argv {
    if arg == "-c" or arg == "-S" or arg == "-E" {
      return true
    }
  }

  return false
}

pure has_option_prefix_argv(argv: List[Str], prefix: Str) -> Bool {
  for arg in argv {
    if arg.starts_with(prefix) {
      return true
    }
  }

  return false
}

pure has_exact_argv(argv: List[Str], value: Str) -> Bool {
  for arg in argv {
    if arg == value {
      return true
    }
  }

  return false
}

pure musl_ldso_name(arch: Str) -> Str {
  if arch == "aarch64" {
    return "ld-musl-aarch64.so.1"
  }

  return f"ld-musl-${arch}.so.1"
}

proc native_cross_cxx_include_args(target_root: Path, target: Str) [fs, error] -> Result[List[Str]] {
  let base = fp"${target_root}/usr/include/c++/15.2.0"
  var include_args: List[Str] = []

  if ! fs.exists(base)? {
    return include_args
  }

  include_args = ["-isystem", base.display()]
  let target_dir = fp"${base}/${target}-linux-musl"
  let alpine_target_dir = fp"${base}/${target}-alpine-linux-musl"

  if fs.exists(target_dir)? {
    include_args = include_args.extend(["-isystem", target_dir.display()])
  }

  if fs.exists(alpine_target_dir)? {
    include_args = include_args.extend(["-isystem", alpine_target_dir.display()])
  }

  return include_args
}

pure strip_cross_driver_args(argv: List[Str]) -> List[Str] {
  var out: List[Str] = []
  var i = 1

  while i < argv.len() {
    let arg = argv[i]

    if (arg == "-target" or arg == "--target" or arg == "--sysroot" or arg == "-isysroot") and i + 1 < argv.len() {
      i += 2
      continue
    }

    if arg.starts_with("--target=") or arg.starts_with("--sysroot=") {
      i += 1
      continue
    }

    out = out.push(arg)
    i += 1
  }

  return out
}

export proc effective_task_argv(argv: List[Str], task_env: Record) [fs, env, error] -> Result[List[Str]] {
  if argv.len() == 0 or task_disables_native_cross(task_env)? or ! native_cross_active() {
    return argv
  }

  let command = argv[0]
  let cxx = is_cxx_compiler_command(command)

  if ! cxx and ! is_c_compiler_command(command) {
    return argv
  }

  let target = native_cross_target_arch()
  let target_root = Path.parse(env_value("LAPUTA_ROOT"))?
  let build_root = Path.parse(env_value("XSH_PM_BUILD_ROOT"))?

  let driver = if cxx {
    fp"${build_root}/usr/lib/llvm22/bin/clang++"
  } else {
    fp"${build_root}/usr/lib/llvm22/bin/clang-22"
  }

  let stripped = strip_cross_driver_args(argv)
  var out: List[Str] = [driver.display(), f"--target=${target}-linux-musl", f"--sysroot=${target_root.display()}"]

  if cxx {
    out = out.extend(native_cross_cxx_include_args(target_root, target)?)
  }

  if ! is_compile_only_argv(argv) and ! has_option_prefix_argv(argv, "-fuse-ld=") {
    out = out.push("-fuse-ld=lld")
  }

  if is_compile_only_argv(argv) {
    return out.extend(stripped)
  }

  if ! has_exact_argv(argv, "-nostdlib") {
    out = out.push("-nostdlib")
  }

  let lib_dir = fp"${target_root}/usr/lib"
  let builtins = fp"${lib_dir}/libclang_rt.builtins-${target}.a"
  var link_args = stripped

  if fs.exists(builtins)? {
    link_args = link_args.push(builtins.display())
  }

  var cxx_lib_args: List[Str] = []

  if cxx {
    cxx_lib_args = ["-lstdc++", "-lunwind", "-lm"]
  }

  if has_exact_argv(argv, "-nostdlib") {
    return out.extend(link_args)
  }

  if has_exact_argv(argv, "-shared") {
    return out.extend(link_args).extend(cxx_lib_args).push("-lc")
  }

  out = out.push(fp"${lib_dir}/Scrt1.o".display()).push(fp"${lib_dir}/crti.o".display())
  out = out.extend(link_args).extend(cxx_lib_args).push("-lc").push(fp"${lib_dir}/crtn.o".display())
  return out.push(f"-Wl,-dynamic-linker,/usr/lib/${musl_ldso_name(target)}")
}

export proc effective_task_env(argv: List[Str], task_env: Record) [env, error] -> Result[Record] {
  if argv.len() == 0 or task_disables_native_cross(task_env)? or ! native_cross_active() {
    return task_env
  }

  let command = argv[0]

  if ! is_cxx_compiler_command(command) and ! is_c_compiler_command(command) and ! is_llvm_tool_command(command) {
    return task_env
  }

  let build_root = Path.parse(env_value("XSH_PM_BUILD_ROOT"))?
  let ld_library_path = f"${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib"
  let path_value = f"${build_root}/usr/lib/llvm-toolchain/bin:${build_root}/usr/bin:${env.get("PATH") ?? ""}"
  return {...task_env, LD_LIBRARY_PATH: ld_library_path, PATH: path_value}
}

proc check_tasks(tasks: List[Record], jobs_count: Int) [error] {
  if jobs_count <= 0 {
    return Err(MakeError.InvalidJobs(message: "job count must be positive"))
  }

  var names: Map[Bool] = {}
  var outputs: Map[Bool] = {}

  for task in tasks {
    if task.name == "" {
      return Err(MakeError.InvalidTask(message: "make task name must not be empty"))
    }

    if names.get(task.name, false) {
      return Err(MakeError.DuplicateTask(message: f"duplicate make task '${task.name}'"))
    }

    if task.argv.len() == 0 {
      return Err(MakeError.InvalidTask(message: f"make task '${task.name}' has empty argv"))
    }

    names[task.name] = true

    for output in task.outputs {
      let key = output.display()

      if key == "" {
        return Err(MakeError.InvalidTask(message: f"make task '${task.name}' has empty output path"))
      }

      if outputs.get(key, false) {
        return Err(MakeError.DuplicateOutput(message: f"duplicate make output '${key}'"))
      }

      outputs[key] = true
    }
  }

  for task in tasks {
    for dep in task.deps {
      if ! names.get(dep, false) {
        return Err(MakeError.MissingDependency(message: f"make task '${task.name}' depends on missing task '${dep}'"))
      }
    }
  }
}

pure dep_path(cwd: Path, dep: Str) -> Path {
  if dep.starts_with("/") {
    return fp"${dep}"
  }

  return fp"${cwd}/${dep}"
}

proc depfile_inputs(depfile: Path, cwd: Path) [fs, error] -> Result[List[Path]] {
  if ! depfile.exists()? {
    let deps: List[Path] = []
    return deps
  }

  let normalized = depfile.read_text()?.replace(
    """\\
""",
    " ",
  )

  let first = normalized.split("""
""")[0]

  if ! first.contains(":") {
    let deps: List[Path] = []
    return deps
  }

  let parts = first.split(":")
  let deps_text = parts[1]
  var deps = [dep_path(cwd, dep) for dep in deps_text.words() if dep != "\\"]
  return deps
}

proc all_inputs(task: Record) [fs, error] -> Result[List[Path]] {
  var inputs = task.inputs

  if has_path(task.depfile) {
    inputs = inputs.extend(depfile_inputs(task.depfile, task.cwd)?)
  }

  return inputs
}

proc output_missing(task: Record) [fs, error] -> Result[Bool] {
  for output in task.outputs {
    if ! output.exists()? {
      return true
    }
  }

  return false
}

proc oldest_output_mtime(outputs: List[Path]) [fs, error] -> Result[Int] {
  var oldest = outputs[0].metadata()?.modified

  for output in outputs {
    let modified = output.metadata()?.modified

    if modified < oldest {
      oldest = modified
    }
  }

  return oldest
}

proc input_newer(task: Record) [fs, error] -> Result[Bool] {
  if task.outputs.len() == 0 {
    return true
  }

  let oldest_output = oldest_output_mtime(task.outputs)?

  for input in all_inputs(task)? {
    if ! input.exists()? {
      return true
    }

    if input.metadata()?.modified > oldest_output {
      return true
    }
  }

  return false
}

proc command_signature(task: Record) [fs, env, error] -> Result[Str] {
  return json.encode(
    {
      argv: effective_task_argv(task.argv, task.env)?,
      cwd: task.cwd.display(),
      env: effective_task_env(task.argv, task.env)?,
    },
  )?
}

proc stamp_changed(task: Record) [fs, env, error] -> Result[Bool] {
  if ! has_path(task.stamp) {
    return false
  }

  if ! task.stamp.exists()? {
    return true
  }

  return task.stamp.read_text()? != command_signature(task)?
}

proc should_run(task: Record) [fs, env, error] -> Result[Bool] {
  if output_missing(task)? {
    return true
  }

  if stamp_changed(task)? {
    return true
  }

  if has_path(task.depfile) and ! task.depfile.exists()? {
    return true
  }

  return input_newer(task)?
}

proc prepare_task_dirs(task: Record) [fs, error] {
  for output in task.outputs {
    output.parent.mkdir()?
  }

  if has_path(task.depfile) {
    task.depfile.parent.mkdir()?
  }

  if has_path(task.stamp) {
    task.stamp.parent.mkdir()?
  }
}

proc run_task(task: Record) [fs, process, env, error] {
  if ! should_run(task)? {
    return
  }

  prepare_task_dirs(task)?

  for output in task.outputs {
    fs.remove(output, missing_ok: true)?
  }

  let task_argv = effective_task_argv(task.argv, task.env)?
  let task_env = effective_task_env(task.argv, task.env)?
  let command = process.command_argv(task_argv[0], task_argv, cwd: task.cwd, env: task_env)
  let status = process.run(command)?

  if ! status.ok {
    return Err(MakeError.CommandFailed(message: f"make task '${task.name}' failed"))
  }

  if has_path(task.stamp) {
    task.stamp.write_atomic(command_signature(task)?)?
  }
}

proc spawn_task(task: Record) [fs, process, env, error] -> Result[Record] {
  prepare_task_dirs(task)?

  for output in task.outputs {
    fs.remove(output, missing_ok: true)?
  }

  let task_argv = effective_task_argv(task.argv, task.env)?
  let task_env = effective_task_env(task.argv, task.env)?
  let handle = spawn process.command_argv(task_argv[0], task_argv, cwd: task.cwd, env: task_env)?
  return {task: task, handle: handle}
}

pure completed_index_key(index: Int) -> Str {
  return f"${index}"
}

proc remove_running_indices(running: List[Record], completed_indices: Map[Bool]) [] -> List[Record] {
  var next: List[Record] = []
  var index = 0

  for row in running {
    if ! completed_indices.get(completed_index_key(index), false) {
      next = next.push(row)
    }

    index += 1
  }

  return next
}

proc cancel_running_uncompleted(running: List[Record], completed_indices: Map[Bool]) [process] {
  var index = 0

  for row in running {
    if ! completed_indices.get(completed_index_key(index), false) {
      match row.handle.cancel() {
        Ok(_) => {}
        Err(_) => {}
      }
    }

    index += 1
  }
}

proc make_progress(message: Str) [env] {
  if (env.get("XSH_MAKE_PROGRESS") ?? "") == "1" or (env.get("XSH_LINUX_KBUILD_PROGRESS") ?? "") == "1" {
    print ${message}
  }
}

pure should_log_dynamic_progress(tasks_count: Int, event_count: Int, running_count: Int, jobs_count: Int) -> Bool {
  if tasks_count <= 100 {
    return true
  }

  if event_count % 100 == 0 {
    return true
  }

  return running_count < jobs_count
}

export proc run_tasks(tasks: List[Record], jobs_count: Int) [fs, process, env, error] -> Result[Unit] {
  check_tasks(tasks, jobs_count)?
  var task_by_name: Map[Record] = {}
  var dependents: Map[List[Str]] = {}
  var remaining_deps: Map[Int] = {}
  var ready: List[Str] = []
  var ready_index = 0
  var done: Map[Bool] = {}
  var scheduled: Map[Bool] = {}
  var running: List[Record] = []
  var pending_stamps: List[Record] = []
  var done_count = 0
  var spawn_count = 0
  var skip_count = 0

  for task in tasks {
    task_by_name[task.name] = task
    remaining_deps[task.name] = task.deps.len()

    if task.deps.len() == 0 {
      ready = ready.push(task.name)
    }

    for dep in task.deps {
      dependents[dep] = dependents.get(dep, empty_strings()).push(task.name)
    }
  }

  make_progress(f"xsh-make-dynamic-start tasks ${tasks.len()} jobs ${jobs_count}")

  while done_count < tasks.len() {
    while running.len() < jobs_count and ready_index < ready.len() {
      let task_name = ready[ready_index]
      ready_index += 1

      if ! scheduled.get(task_name, false) {
        let task = task_by_name.get(task_name)?
        scheduled[task.name] = true

        if should_run(task)? {
          running = running.push(spawn_task(task)?)
          spawn_count += 1

          if should_log_dynamic_progress(tasks.len(), spawn_count, running.len(), jobs_count) {
            make_progress(
              f"xsh-make-dynamic-spawn done ${done_count}/${tasks.len()} running ${running.len()} ready ${ready.len() - ready_index} spawned ${spawn_count} task ${task.name}",
            )
          }
        } else {
          done[task.name] = true
          done_count += 1
          skip_count += 1

          if should_log_dynamic_progress(tasks.len(), skip_count, running.len(), jobs_count) {
            make_progress(
              f"xsh-make-dynamic-skip done ${done_count}/${tasks.len()} running ${running.len()} ready ${ready.len() - ready_index} skipped ${skip_count} task ${task.name}",
            )
          }

          for dependent in dependents.get(task.name, empty_strings()) {
            let remaining = remaining_deps.get(dependent, 0) - 1
            remaining_deps[dependent] = remaining

            if remaining == 0 {
              ready = ready.push(dependent)
            }
          }
        }
      }
    }

    break when done_count >= tasks.len()

    if running.len() == 0 {
      return Err(MakeError.DependencyCycle(message: "cycle in make task graph"))
    }

    make_progress(
      f"xsh-make-dynamic-wait done ${done_count}/${tasks.len()} running ${running.len()} ready ${ready.len() - ready_index} jobs ${jobs_count}",
    )

    let completed_rows = process.wait_ready([row.handle for row in running])?
    var completed_indices: Map[Bool] = {}
    var completed_tasks: List[Record] = []

    for completed in completed_rows {
      let completed_index: Int = completed.index
      let row = running[completed_index]
      completed_indices[completed_index_key(completed_index)] = true

      if ! completed.status.ok {
        cancel_running_uncompleted(running, completed_indices)
        return Err(MakeError.CommandFailed(message: f"make task '${row.task.name}' failed"))
      }

      completed_tasks = completed_tasks.push(row)
    }

    running = remove_running_indices(running, completed_indices)

    for row in completed_tasks {
      pending_stamps = pending_stamps.push(row)
      done[row.task.name] = true
      done_count += 1

      for dependent in dependents.get(row.task.name, empty_strings()) {
        let remaining = remaining_deps.get(dependent, 0) - 1
        remaining_deps[dependent] = remaining

        if remaining == 0 {
          ready = ready.push(dependent)
        }
      }

      while running.len() < jobs_count and ready_index < ready.len() {
        let task_name = ready[ready_index]
        ready_index += 1

        if ! scheduled.get(task_name, false) {
          let task = task_by_name.get(task_name)?
          scheduled[task.name] = true

          if should_run(task)? {
            running = running.push(spawn_task(task)?)
            spawn_count += 1

            if should_log_dynamic_progress(tasks.len(), spawn_count, running.len(), jobs_count) {
              make_progress(
                f"xsh-make-dynamic-spawn done ${done_count}/${tasks.len()} running ${running.len()} ready ${ready.len() - ready_index} spawned ${spawn_count} task ${task.name}",
              )
            }
          } else {
            done[task.name] = true
            done_count += 1
            skip_count += 1

            if should_log_dynamic_progress(tasks.len(), skip_count, running.len(), jobs_count) {
              make_progress(
                f"xsh-make-dynamic-skip done ${done_count}/${tasks.len()} running ${running.len()} ready ${ready.len() - ready_index} skipped ${skip_count} task ${task.name}",
              )
            }

            for dependent in dependents.get(task.name, empty_strings()) {
              let remaining = remaining_deps.get(dependent, 0) - 1
              remaining_deps[dependent] = remaining

              if remaining == 0 {
                ready = ready.push(dependent)
              }
            }
          }
        }
      }
    }

    if should_log_dynamic_progress(tasks.len(), done_count, running.len(), jobs_count) {
      make_progress(
        f"xsh-make-dynamic-complete done ${done_count}/${tasks.len()} running ${running.len()} ready ${ready.len() - ready_index} batch ${completed_rows.len()}",
      )
    }
  }

  for row in pending_stamps {
    if has_path(row.task.stamp) {
      row.task.stamp.write_atomic(command_signature(row.task)?)?
    }
  }
}

export proc compile_lo_task(
  toolchain: Path,
  triple: Str,
  cflags: List[Str],
  defs: List[Str],
  includes: List[Str],
  src: Path,
  out: Path,
  deps: List[Str] = [],
) [] -> MakeTask {
  let _ = toolchain
  let depfile = depfile_path(out)
  var argv: List[Str] = ["cc", "-target", triple, "-c", "-fPIC", "-DPIC"]
  argv = argv.extend(cflags).extend(defs).extend(includes)
  argv = argv.extend([src.display(), "-o", out.display(), "-MMD", "-MP", "-MF", depfile.display()])

  return {
    name: out.display(),
    outputs: [out],
    inputs: [src],
    deps: deps,
    argv: argv,
    cwd: p".",
    env: {},
    depfile: depfile,
    stamp: stamp_path(out),
  }
}

export proc compile_cxx_task(
  toolchain: Path,
  triple: Str,
  cflags: List[Str],
  defs: List[Str],
  includes: List[Str],
  src: Path,
  out: Path,
  deps: List[Str] = [],
) [] -> MakeTask {
  let _ = toolchain
  let depfile = depfile_path(out)
  var argv: List[Str] = ["c++", "-target", triple, "-c"]
  argv = argv.extend(cflags).extend(defs).extend(includes)
  argv = argv.extend([src.display(), "-o", out.display(), "-MMD", "-MP", "-MF", depfile.display()])

  return {
    name: out.display(),
    outputs: [out],
    inputs: [src],
    deps: deps,
    argv: argv,
    cwd: p".",
    env: {},
    depfile: depfile,
    stamp: stamp_path(out),
  }
}

export proc compile_c_task(
  toolchain: Path,
  triple: Str,
  cflags: List[Str],
  defs: List[Str],
  includes: List[Str],
  src: Path,
  out: Path,
  deps: List[Str] = [],
) [] -> MakeTask {
  let depfile = depfile_path(out)
  var argv: List[Str] = [toolchain.display(), "-target", triple, "-c"]
  argv = argv.extend(cflags).extend(defs).extend(includes)
  argv = argv.extend([src.display(), "-o", out.display(), "-MMD", "-MP", "-MF", depfile.display()])

  return {
    name: out.display(),
    outputs: [out],
    inputs: [src],
    deps: deps,
    argv: argv,
    cwd: p".",
    env: {},
    depfile: depfile,
    stamp: stamp_path(out),
  }
}

export proc link_shared_task(
  toolchain: Path,
  triple: Str,
  objs: List[Path],
  soname: Str,
  ldflags: List[Str],
  out: Path,
  deps: List[Str] = [],
) [] -> MakeTask {
  let _ = toolchain
  var argv: List[Str] = ["cc", "-target", triple, "-shared", f"-Wl,-soname,${soname}"]
  argv = argv.extend(ldflags).extend(path_args(objs)).extend(["-o", out.display()])

  return {
    name: out.display(),
    outputs: [out],
    inputs: objs,
    deps: deps,
    argv: argv,
    cwd: p".",
    env: {},
    depfile: empty_path(),
    stamp: stamp_path(out),
  }
}

export proc link_executable_cxx_task(
  toolchain: Path,
  triple: Str,
  objs: List[Path],
  libs: List[Path],
  ldflags: List[Str],
  out: Path,
  deps: List[Str] = [],
) [] -> MakeTask {
  let _ = toolchain
  var argv: List[Str] = ["c++", "-target", triple]
  argv = argv.extend(path_args(objs)).extend(path_args(libs)).extend(ldflags).extend(["-o", out.display()])

  return {
    name: out.display(),
    outputs: [out],
    inputs: objs.extend(libs),
    deps: deps,
    argv: argv,
    cwd: p".",
    env: {},
    depfile: empty_path(),
    stamp: stamp_path(out),
  }
}

# Link an executable from .o objects and shared library files.
# libs are full paths to .so files linked directly (SONAME comes from the library).
export proc link_executable_task(
  toolchain: Path,
  triple: Str,
  objs: List[Path],
  libs: List[Path],
  ldflags: List[Str],
  out: Path,
  deps: List[Str] = [],
) [] -> MakeTask {
  let _ = toolchain
  var argv: List[Str] = ["cc", "-target", triple]
  argv = argv.extend(path_args(objs)).extend(path_args(libs)).extend(ldflags).extend(["-o", out.display()])

  return {
    name: out.display(),
    outputs: [out],
    inputs: objs.extend(libs),
    deps: deps,
    argv: argv,
    cwd: p".",
    env: {},
    depfile: empty_path(),
    stamp: stamp_path(out),
  }
}

export proc link_archive_task(toolchain: Path, objs: List[Path], out: Path, deps: List[Str] = []) [] -> MakeTask {
  let _ = toolchain
  var argv: List[Str] = ["ar", "rcs", out.display()]
  argv = argv.extend(path_args(objs))

  return {
    name: out.display(),
    outputs: [out],
    inputs: objs,
    deps: deps,
    argv: argv,
    cwd: p".",
    env: {},
    depfile: empty_path(),
    stamp: stamp_path(out),
  }
}

# Compile a .c file to a position-independent .lo object (for shared libraries).
# out is the full path of the output object file; parent directories are created.
export proc compile_lo(
  toolchain: Path,
  triple: Str,
  cflags: List[Str],
  defs: List[Str],
  includes: List[Str],
  src: Path,
  out: Path,
) [fs, process, env, error] -> Result[Unit] {
  run_tasks([compile_lo_task(toolchain, triple, cflags, defs, includes, src, out)], 1)?
}

# Compile a .cxx/.cpp file to a regular .o object using the C++ compiler.
export proc compile_cxx(
  toolchain: Path,
  triple: Str,
  cflags: List[Str],
  defs: List[Str],
  includes: List[Str],
  src: Path,
  out: Path,
) [fs, process, env, error] -> Result[Unit] {
  run_tasks([compile_cxx_task(toolchain, triple, cflags, defs, includes, src, out)], 1)?
}

# Compile a .c file to a regular .o object (for executables).
export proc compile_c(
  toolchain: Path,
  triple: Str,
  cflags: List[Str],
  defs: List[Str],
  includes: List[Str],
  src: Path,
  out: Path,
) [fs, process, env, error] -> Result[Unit] {
  run_tasks([compile_c_task(toolchain, triple, cflags, defs, includes, src, out)], 1)?
}

# Link a shared library from .lo objects with a given SONAME.
export proc link_shared(
  toolchain: Path,
  triple: Str,
  objs: List[Path],
  soname: Str,
  ldflags: List[Str],
  out: Path,
) [fs, process, env, error] -> Result[Unit] {
  run_tasks([link_shared_task(toolchain, triple, objs, soname, ldflags, out)], 1)?
}

# Link a C++ executable using the C++ compiler driver.
export proc link_executable_cxx(
  toolchain: Path,
  triple: Str,
  objs: List[Path],
  libs: List[Path],
  ldflags: List[Str],
  out: Path,
) [fs, process, env, error] -> Result[Unit] {
  run_tasks([link_executable_cxx_task(toolchain, triple, objs, libs, ldflags, out)], 1)?
}

export proc link_executable(
  toolchain: Path,
  triple: Str,
  objs: List[Path],
  libs: List[Path],
  ldflags: List[Str],
  out: Path,
) [fs, process, env, error] -> Result[Unit] {
  run_tasks([link_executable_task(toolchain, triple, objs, libs, ldflags, out)], 1)?
}

# Create a static archive from .lo/.o objects.
export proc link_archive(toolchain: Path, objs: List[Path], out: Path) [fs, process, env, error] -> Result[Unit] {
  run_tasks([link_archive_task(toolchain, objs, out)], 1)?
}
