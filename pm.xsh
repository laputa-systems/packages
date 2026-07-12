#!/usr/bin/env -S XSH_MODULE_PATH=.:/usr/lib/pm /bin/xsh
use pm.cli as pm_cli

proc main(...argv: List[Str]) [fs, net, process, env, time, error] {
  pm_cli.run_pm_cli(argv)?
}

main(@args)?
