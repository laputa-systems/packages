use pm.make as make
use pm.util as pm_util

export let name = "tmux"

export let ver = "next-3.7"

export let rel = "8"

export let deps = ["musl", "libevent", "utf8proc"]

export let mkdeps = ["llvm-toolchain", "pkgconf"]

# Source is a fixed GitHub commit archive (no VERSION substitution needed).
export let sources = [
  p"https://github.com/laputa-systems/tmux/archive/f83a6070f75a66d9ac6d4e897544e85302b8ec4b.tar.gz",
  p"files/cmd-parse.c",
  p"files/cmd-parse.h",
]

export let checksums = [
  "fc47986264c2102cc0cbecd97d5d8a1e296c5ac8cb245da8af58bdd6abd313e8",
  "eb2d780fa143be299bc37db68e745347214d2f8dffe64bab4befc3048573c2dc",
  "838324384f77cd41f0d9de9ba36b980e437efdf54e136b8a1854bee58cf6882f",
]

export let filetree = [
  {path: p"usr/bin/tmux", kind: "binary"},
]

proc write_config_h() [fs, error] {
  fs.write(
    p"config.h",
    """#ifndef CONFIG_H
#define CONFIG_H

#define _GNU_SOURCE 1

#define HAVE_DIRENT_H 1
#define HAVE_ERR_H 1
#define HAVE_EVENT2_EVENT_H 1
#define HAVE_FCNTL_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_PATHS_H 1
#define HAVE_PTY_H 1
#define HAVE_STDINT_H 1

#define HAVE_ASPRINTF 1
#define HAVE_CFMAKERAW 1
#define HAVE_CLOCK_GETTIME 1
#define HAVE_DAEMON 1
#define HAVE_DIRFD 1
#define HAVE_EXPLICIT_BZERO 1
#define HAVE_FLOCK 1
#define HAVE_FORKPTY 1
#define HAVE_GETDTABLESIZE 1
#define HAVE_GETLINE 1
#define HAVE_MEMMEM 1
#define HAVE_PROC_PID 1
#define HAVE_PRCTL 1
#define HAVE_PR_SET_NAME 1
#define HAVE_REALLOCARRAY 1
#define HAVE_SETENV 1
#define HAVE_SO_PEERCRED 1
#define HAVE_STRCASESTR 1
#define HAVE_STRLCAT 1
#define HAVE_STRLCPY 1
#define HAVE_STRNDUP 1
#define HAVE_STRNLEN 1
#define HAVE_STRSEP 1
#define HAVE_SYSCONF 1
#define HAVE_UTF8PROC 1
#define HAVE___PROGNAME 1

#endif
""",
  )?
}

proc build_tmux(cc: Path) [fs, process, env, error] -> Result[Path] {
  let core_sources = """
alerts.c arguments.c attributes.c cfg.c client.c cmd.c colour.c
control.c control-notify.c environ.c file.c format.c format-draw.c
grid.c grid-reader.c grid-view.c hyperlinks.c input.c input-keys.c
job.c key-bindings.c key-string.c layout.c layout-custom.c layout-set.c
log.c menu.c mode-tree.c names.c notify.c options.c options-table.c
paste.c popup.c proc.c regsub.c resize.c screen.c screen-redraw.c
screen-write.c server.c server-acl.c server-client.c server-fn.c
session.c sort.c spawn.c status.c style.c tmux.c tty.c tty-acs.c
tty-draw.c tty-features.c tty-keys.c tty-term.c utf8.c utf8-combined.c
window.c window-buffer.c window-client.c window-clock.c window-copy.c
window-customize.c window-tree.c xmalloc.c
cmd-attach-session.c cmd-bind-key.c cmd-break-pane.c cmd-capture-pane.c
cmd-choose-tree.c cmd-command-prompt.c cmd-confirm-before.c cmd-copy-mode.c
cmd-detach-client.c cmd-display-menu.c cmd-display-message.c
cmd-display-panes.c cmd-find.c cmd-find-window.c cmd-if-shell.c
cmd-join-pane.c cmd-kill-pane.c cmd-kill-server.c cmd-kill-session.c
cmd-kill-window.c cmd-list-buffers.c cmd-list-clients.c cmd-list-commands.c
cmd-list-keys.c cmd-list-panes.c cmd-list-sessions.c cmd-list-windows.c
cmd-load-buffer.c cmd-lock-server.c cmd-move-window.c cmd-new-session.c
cmd-new-window.c cmd-paste-buffer.c cmd-pipe-pane.c cmd-queue.c
cmd-refresh-client.c cmd-rename-session.c cmd-rename-window.c
cmd-resize-pane.c cmd-resize-window.c cmd-respawn-pane.c
cmd-respawn-window.c cmd-rotate-window.c cmd-run-shell.c cmd-save-buffer.c
cmd-select-layout.c cmd-select-pane.c cmd-select-window.c cmd-send-keys.c
cmd-server-access.c cmd-set-buffer.c cmd-set-environment.c cmd-set-option.c
cmd-show-environment.c cmd-show-messages.c cmd-show-options.c
cmd-show-prompt-history.c cmd-source-file.c cmd-split-window.c
cmd-swap-pane.c cmd-swap-window.c cmd-switch-client.c cmd-unbind-key.c
cmd-wait-for.c
""".words()

  let compat_sources = """
compat/closefrom.c compat/daemon.c compat/fdforkpty.c compat/freezero.c
compat/getdtablecount.c compat/getopt_long.c compat/htonll.c
compat/imsg.c compat/imsg-buffer.c compat/ntohll.c compat/recallocarray.c
compat/setproctitle.c compat/vis.c compat/unvis.c compat/base64.c
compat/fgetln.c compat/getpeereid.c compat/getprogname.c compat/strtonum.c
compat/utf8proc.c
""".words()

  let generated_sources = ["cmd-parse.c", "osdep-linux.c"]
  let tmux_sources = [fp"${source}" for source in core_sources.extend(generated_sources).extend(compat_sources)]
  let pc = make.pkg_config_flags(["libevent_core", "libutf8proc"])?

  let cflags = [
    "-std=gnu99",
    "-include",
    "config.h",
    "-iquote.",
    "-O2",
    "-Wno-deprecated-declarations",
    "-Wno-macro-redefined",
    f"-DTMUX_VERSION=\"${ver}\"",
    "-DTMUX_CONF=\"/etc/tmux.conf:~/.tmux.conf:~/.config/tmux/tmux.conf\"",
    "-DTMUX_LOCK_CMD=\"lock -np\"",
    "-DTMUX_TERM=\"tmux-256color\"",
  ].extend(pc.cflags)

  let arch = pm_util.target_arch()?

  let tmux = make.c_program({
    cc,
    triple: f"${arch}-linux-musl",
    cflags,
    defs: [],
    includes: [],
    root: p".",
    sources: tmux_sources,
    out_dir: p"build",
    out: p"tmux",
    libs: [],
    ldflags: pc.libs.extend(["-lm"]),
    deps: [],
  })

  make.run_tasks(tmux.tasks, make.jobs()?)?
  return tmux.output
}

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  write_config_h()?
  let tmux = build_tmux(cc)?
  fs.install(tmux, fp"${dest}/usr/bin/tmux", 0o755, parents: true, overwrite: true)?
}
