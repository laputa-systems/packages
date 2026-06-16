export let name: Str = "laputa-pm"

export let ver: Str = "1"

export let rel: Str = "5"

export let deps: List[Str] = ["xsh"]

export let mkdeps: List[Str] = []

export let sources: List[Path] = [../../pm.xsh, p"../../pm => pm"]

export let checksums: List[Str] = ["SKIP", "SKIP"]

export proc build(dest: Path) [fs, env, error] {
  fs.install(p"pm.xsh", fp"${dest}/usr/lib/pm/pm.xsh", 0o644, parents: true, overwrite: true)?
  let _ = fs.copy_tree(p"pm", fp"${dest}/usr/lib/pm/pm", parents: true, overwrite: true)?
  fs.mkdir(fp"${dest}/usr/bin")?

  fs.write(
    fp"${dest}/usr/bin/pm",
    """#!/usr/local/bin/xsh --
error WrapperError = Failed(message: Str)

proc usage() {
  print "usage: pm COMMAND [ARG...]"
}

proc main(...argv: List[Str]) [fs, process, env, error] {
  if argv.len() == 0 {
    usage()
    return
  }

  let repo = env.get("XSH_PM_REPO") ?? env.get("LAPUTA_REPO") ?? "https://laputa.17166969.xyz"
  let work = env.get("XSH_PM_WORK") ?? "/var/cache/pm/work"
  let out = env.get("XSH_PM_OUT") ?? "/var/cache/pm/out"
  let command = argv[0]
  var forwarded: List[Str] = ["xsh", "/usr/lib/pm/pm.xsh", "--", command, "/", work, out]
  var index = 1

  if command == "world-plan" or command == "help" or command == "-h" or command == "--help" {
    forwarded = ["xsh", "/usr/lib/pm/pm.xsh", "--", command]
  }

  while index < argv.len() {
    forwarded = forwarded.push(argv[index])
    index += 1
  }

  let status = process.run(
    process.command_argv(
      /usr/local/bin/xsh,
      forwarded,
      /,
      {XSH_MODULE_PATH: "/usr/lib/pm", XSH_PM_REPO: repo, XSH_PM_PUBLIC_REPO: repo},
    ),
  )?

  if ! status.ok {
    if status.exited() {
      abort(status.exit_code()?)
    }

    return Err(WrapperError.Failed("pm command was signaled"))
  }
}

main(@args)?
""",
  )?

  fs.chmod(fp"${dest}/usr/bin/pm", 0o755)?
}
