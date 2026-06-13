use pm.proof as proof
use pm.util as pm_util

error ScriptError = Failed(kind: Str, message: Str)

proc ensure(condition: Bool, kind: Str, message: Str) [error] {
  if ! condition {
    Err(ScriptError.Failed(kind, message))?
  }
}

proc main(rootfs: Path = /rootfs) [fs, process, env, time, error] {
  let os = system.uname()?
  let dynlinker = fp"${rootfs}/usr/lib/ld-musl-${os.machine}.so.1"
  let shell = fp"${rootfs}/usr/bin/sh"
  let tmux = fp"${rootfs}/usr/bin/tmux"
  proof.target_elf(rootfs, p"usr/bin/tmux", "tmux")?
  let build_arch = pm_util.build_arch()?
  let target_arch = pm_util.target_arch()?

  if build_arch != target_arch {
    print f"tmux ok: cross-built ${target_arch}"
    return
  }

  let tmp_root = fs.tempdir()?
  defer fs.close_root(tmp_root)?
  let tmp = fs.root_path(tmp_root)?
  let label = "laputa-proof"
  let config = fp"${tmp}/tmux.conf"
  fs.mkdir(fp"${tmp}/home")?
  ensure(fs.exists(dynlinker)?, "tmux-proof", f"missing rootfs musl loader: ${dynlinker.display()}")?
  ensure(fs.exists(shell)?, "tmux-proof", f"missing rootfs shell: ${shell.display()}")?
  ensure(fs.exists(tmux)?, "tmux-proof", f"missing rootfs tmux binary: ${tmux.display()}")?

  fs.write(
    config,
    """set -g default-terminal "tmux-256color"
set -ga terminal-features "tmux-256color:Sync"
set -as terminal-features ",screen*:256:clipboard:ccolour:cstyle:focus:title"
set -g set-clipboard external
set -sg escape-time 0
set -g focus-events on
""",
  )?

  env {
    HOME = fp"${tmp}/home".display()
    LD_LIBRARY_PATH = fp"${rootfs}/usr/lib".display()
    PS1 = "laputa$ "
    SHELL = shell.display()
    TERM = "tmux-256color"
    TMUX_TMPDIR = tmp.display()
  } {
    run $dynlinker $tmux "-L" $label "-f" $config "new-session" "-d" "-s" "proof" "-x" "80" "-y" "24" $shell "--no-config" ?
    time.sleep(500ms)?
    let sessions = run.text $dynlinker $tmux "-L" $label "list-sessions" ?
    ensure("proof:" in sessions, "tmux-session", f"tmux did not report proof session: ${sessions.trim()}")?
    let default_terminal = run.text $dynlinker $tmux "-L" $label "show-options" "-gqv" "default-terminal" ?

    ensure(
      default_terminal.trim() == "tmux-256color",
      "tmux-config",
      f"default-terminal was ${default_terminal.trim()}",
    )?

    let terminal_features = run.text $dynlinker $tmux "-L" $label "show-options" "-gqv" "terminal-features" ?

    ensure(
      "tmux-256color:Sync" in terminal_features,
      "tmux-config",
      f"missing Sync terminal feature: ${terminal_features.trim()}",
    )?

    ensure(
      "screen*:256:clipboard:ccolour:cstyle:focus:title" in terminal_features,
      "tmux-config",
      f"missing screen terminal features: ${terminal_features.trim()}",
    )?

    let set_clipboard = run.text $dynlinker $tmux "-L" $label "show-options" "-gqv" "set-clipboard" ?
    ensure(set_clipboard.trim() == "external", "tmux-config", f"set-clipboard was ${set_clipboard.trim()}")?
    let escape_time = run.text $dynlinker $tmux "-L" $label "show-options" "-sgqv" "escape-time" ?
    ensure(escape_time.trim() == "0", "tmux-config", f"escape-time was ${escape_time.trim()}")?
    let focus_events = run.text $dynlinker $tmux "-L" $label "show-options" "-gqv" "focus-events" ?
    ensure(focus_events.trim() == "on", "tmux-config", f"focus-events was ${focus_events.trim()}")?
    run $dynlinker $tmux "-L" $label "send-keys" "-t" "proof:0.0" "print \"tmux-proof-alpha\"" "C-m" ?
    run $dynlinker $tmux "-L" $label "send-keys" "-t" "proof:0.0" "print \"tmux-proof-edit:ba" "BSpace" "BSpace" "ok\"" "C-m" ?
    time.sleep(1000ms)?
    let pane = run.text $dynlinker $tmux "-L" $label "capture-pane" "-pt" "proof:0.0" ?
    ensure("tmux-proof-alpha" in pane, "tmux-pane", f"tmux pane did not capture alpha output: ${pane.trim()}")?

    ensure(
      "tmux-proof-edit:ok" in pane,
      "tmux-pane",
      f"tmux pane did not capture edited command output: ${pane.trim()}",
    )?

    run $dynlinker $tmux "-L" $label "new-window" "-d" "-n" "check" $shell "--no-config" ?
    let windows = run.text $dynlinker $tmux "-L" $label "list-windows" ?
    ensure("check" in windows, "tmux-window", f"tmux did not report created window: ${windows.trim()}")?
    run $dynlinker $tmux "-L" $label "kill-server" ?
    let dead = run.status $dynlinker $tmux "-L" $label "has-session" "-t" "proof" 2> /dev/null
    ensure(! dead.ok, "tmux-stop", "tmux server still reported the proof session after kill-server")?
  } ?

  print "tmux ok: config, pty capture, window creation, clean stop"
}

main(@args)?
