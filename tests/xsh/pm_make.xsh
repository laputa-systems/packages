##! Typed task scheduling, argv, stamp reuse, and failed-peer cleanup.
use pm.make as make

type TaskOutput = {arguments: List[Str], environment: Str}

proc task_runner() [env, process, error] -> Result[Path] {
  let configured = env.get("XSH_HOST") ?? ""
  if configured != "" { return fp"${configured}" }
  process.which("xsh")?
}

pure task(name: Str, root: Path, command: List[Any], outputs: List[Path], inputs: List[Path] = [], deps: List[Str] = []) -> make.MakeTask {
  {
    name,
    outputs,
    inputs,
    deps,
    argv: command,
    cwd: root,
    env: {TASK_LABEL: "literal environment value"},
    depfile: p"",
    stamp: fp"${root}/${name}.cmd",
  }
}

test make_tasks_preserve_typed_argv_dependencies_and_stamp_reuse [fs, process, env, error] { |ctx|
  let root = test.temp_dir(ctx, name: "make task argv")?
  let script = fp"${root}/task runner.xsh"
  script.write(r"""let output = fp"${args[0]}"
let counter = fp"${args[2]}"
if args.len() > 3 { let _ = fp"${args[3]}".read_text()? }
counter.write((counter.read_text() ?? "") + "x")?
json.write(output, {arguments: args, environment: env.get("TASK_LABEL") ?? ""})?
""")?
  let runner = task_runner()?
  let first_output = fp"${root}/first output.json"
  let second_output = fp"${root}/second output.json"
  let first_counter = fp"${root}/first count"
  let second_counter = fp"${root}/second count"
  let payload = "spaces 'quotes' $literal"
  let first = task("first", root, [runner, script, "--", first_output, payload, first_counter], [first_output], [script])
  let second = task("second", root, [runner, script, "--", second_output, payload, second_counter, first_output], [second_output], [script, first_output], ["first"])
  make.run_tasks([second, first], 2)?
  let observed = json.read(second_output)?.require(TaskOutput)?
  assert observed.arguments == [second_output.display(), payload, second_counter.display(), first_output.display()]
  assert observed.environment == "literal environment value"
  assert first_counter.read_text()? == "x"
  assert second_counter.read_text()? == "x"
  make.run_tasks([second, first], 2)?
  assert first_counter.read_text()? == "x"
  assert second_counter.read_text()? == "x"
}

test make_tasks_cancel_running_peers_and_do_not_publish_failed_stamps [fs, process, env, time, error] { |ctx|
  let root = test.temp_dir(ctx, name: "failed make tasks")?
  let peer_script = fp"${root}/peer.xsh"
  let failure_script = fp"${root}/failure.xsh"
  let started = fp"${root}/started"
  let late_output = fp"${root}/late output"
  peer_script.write(r"""fp"${args[0]}".write("started")?
run sh -c "sleep 1" ?
fp"${args[1]}".write("should have been cancelled")?
""")?
  failure_script.write(r"""while ! fp"${args[0]}".exists()? { time.sleep(10ms)? }
error.fail("task fixture failed")?
""")?
  let runner = task_runner()?
  let peer = task("peer", root, [runner, peer_script, "--", started, late_output], [late_output])
  let failure = task("failure", root, [runner, failure_script, "--", started], [fp"${root}/failure output"])
  match make.run_tasks([peer, failure], 2) {
    Ok(_) => test.fail("failed command unexpectedly completed its task graph")?
    Err(problem) => {
      assert problem is ProcessFailure
      assert problem.message == "make task 'failure' failed"
    }
  }
  assert started.exists()?
  time.sleep(1100ms)?
  assert ! late_output.exists()?
  assert ! peer.stamp.exists()?
  assert ! failure.stamp.exists()?
}

test make_pkg_config_flags_preserve_checked_compiler_and_linker_lists [fs, process, env, error] { |ctx|
  let root = test.temp_dir(ctx, name: "pkg config flags")?
  let runner = task_runner()?
  let tool = fp"${root}/pkg-config"
  tool.write(f"""#!${runner.display()}
if args == ["--cflags", "libone", "libtwo"] {
  print "-I/usr/include/example -DEXAMPLE=1"
} else if args == ["--libs", "libone", "libtwo"] {
  print "-L/usr/lib/example -lexample"
} else {
  error.fail("unexpected pkg-config arguments")?
}
""")?
  tool.chmod(0o755)?
  env ({PATH: f"${root}:${env.get("PATH") ?? ""}", XSH_PM_TARGET_ROOT: ""}) {
    let flags = make.pkg_config_flags(["libone", "libtwo"])?
    assert flags.cflags == ["-I/usr/include/example", "-DEXAMPLE=1"]
    assert flags.libs == ["-L/usr/lib/example", "-lexample"]
  } ?
}
