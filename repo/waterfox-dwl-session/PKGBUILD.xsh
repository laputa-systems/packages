export let name: Str = "waterfox-dwl-session"

export let ver: Str = "1"

export let rel: Str = "17"

export let deps: List[Str] = [
  "waterfox-bin",
  "dwl-minimal",
  "seatd",
  "mdevd",
  "libudev-zero",
  "ca-certificates",
  "foot-minimal",
]

export let mkdeps: List[Str] = []

export let sources: List[Path] = []

export let checksums: List[Str] = []

proc install_session(dest: Path) [fs, error] {
  fs.write(
    fp"${dest}/usr/bin/waterfox-dwl-session",
    """#!/usr/local/bin/xsh --
error SessionError = Failed(kind: Str, message: Str)

proc marker(line: Str) [fs] {
  match fs.write(/dev/console, f"\${line}\\n") {
    Ok(_) => {}
    Err(_) => {}
  }
}

proc ensure_dir(path_value: Path, mode: Int) [fs, error] {
  if ! fs.exists(path_value)? {
    path_value.mkdir()?
  }

  fs.chmod(path_value, mode)?
}

proc wait_for_socket(path_value: Path) [fs, time, error] {
  var tries = 50

  while tries > 0 {
    if fs.exists(path_value)? {
      let mode_class = path_value.metadata()?.mode / 4096 % 16

      if mode_class == 12 {
        return
      }
    }

    time.sleep(100ms)?
    tries -= 1
  }

  return Err(SessionError.Failed("seatd", f"seatd did not create \${path_value.display()}"))
}

proc terminate_if_live(pid: Int) [process] {
  match process.kill(pid, signal: "TERM") {
    Ok(_) => {}
    Err(_) => {}
  }
}

proc wait_for_path(path_value: Path, kind: Str, message: Str) [fs, time, error] {
  var tries = 100

  while tries > 0 {
    if fs.exists(path_value)? {
      return
    }

    time.sleep(100ms)?
    tries -= 1
  }

  return Err(SessionError.Failed(kind, message))
}

proc start_mdevd() [fs, process, error] {
  if ! fs.exists(/usr/bin/mdevd)? {
    return
  }

  let _mdevd = spawn process.command_argv(
    /usr/bin/mdevd,
    ["mdevd", "-O", "4", "-f", "/etc/mdev.conf", "-C"],
    env: {PATH: "/usr/local/bin:/usr/bin:/bin"},
  )?

  marker("waterfox-session mdevd ok")
}

proc prepare_runtime_dir() [fs, error] {
  ensure_dir(/run/user, 0o755)?
  ensure_dir(/run/user/1000, 0o700)?
  fs.chown(/run/user/1000, user.by_uid(1000)?)?
  fs.chgrp(/run/user/1000, group.by_gid(1000)?)?
  fs.chmod(/run/user/1000, 0o700)?
}

proc prepare_console() [fs, error] {
  if fs.exists(/dev/console)? {
    fs.chgrp(/dev/console, group.by_gid(5)?)?
    fs.chmod(/dev/console, 0o620)?
  }
}

pure startup_command(mode: Str) -> Str {
  if mode == "terminal" {
    return "/usr/bin/foot"
  }

  if mode == "clipboard" {
    return "/usr/local/bin/xsh /usr/bin/waterfox-session-clipboard-proof"
  }

  return "/usr/bin/waterfox about:blank"
}

proc run_user_session(mode: Str) [fs, process, time, error] {
  let startup = startup_command(mode)

  marker("waterfox-session user entered")

  env {
    LIBSEAT_BACKEND = "seatd"
    MOZ_CRASHREPORTER_DISABLE = "1"
    MOZ_DISABLE_AUTO_SAFE_MODE = "1"
    MOZ_ENABLE_WAYLAND = "1"
    NO_AT_BRIDGE = "1"
    PATH = "/usr/local/bin:/usr/bin:/bin"
    SEATD_SOCK = "/run/seatd.sock"
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt"
    WAYLAND_DISPLAY = "wayland-0"
    WLR_BACKENDS = "drm,libinput"
    WLR_DRM_NO_ATOMIC = "1"
    WLR_LIBINPUT_NO_DEVICES = "0"
    WLR_RENDERER = "pixman"
    WLR_SCENE_DISABLE_DIRECT_SCANOUT = "1"
    WLR_SCENE_DISABLE_VISIBILITY = "1"
    XDG_RUNTIME_DIR = "/run/user/1000"
  } {
    if mode == "clipboard" {
      let done = /run/user/1000/waterfox-clipboard-ok
      fs.remove(done, missing_ok: true)?
      let compositor = spawn process.command_argv(
        /usr/bin/dwl,
        ["dwl"],
        timeout: 20s,
      )?

      wait_for_path(/run/user/1000/wayland-0, "wayland", "dwl did not create wayland-0")?
      run /usr/local/bin/xsh /usr/bin/waterfox-session-clipboard-proof ?
      wait_for_path(done, "clipboard", "clipboard proof did not complete")?
      terminate_if_live(compositor.pid)

      match wait compositor {
        Ok(_) => {}
        Err(ProcessError.Timeout {message: _}) => terminate_if_live(compositor.pid)
        Err(e) => return Err(SessionError.Failed("dwl", f"clipboard dwl wait failed: \${e.message}"))
      }

      return
    }

    let status = run.status /usr/bin/dwl "-s" $startup ?

    if ! status.ok {
      let code = status.exit_code()?
      marker(f"waterfox-session user dwl failed code=\${code}")
      return Err(SessionError.Failed("dwl", f"dwl exited with code \${code}"))
    }
  } ?
}

proc run_root_session(mode: Str) [fs, process, time, error] {
  start_mdevd()?
  prepare_runtime_dir()?
  prepare_console()?
  let socket = /run/seatd.sock
  fs.remove(socket, missing_ok: true)?
  let _seatd = spawn process.command_argv(
    /usr/bin/seatd,
    ["seatd", "-g", "seat", "-l", "info"],
    env: {PATH: "/usr/local/bin:/usr/bin:/bin", SEATD_VTBOUND: "0"},
  )?
  wait_for_socket(socket)?
  marker("waterfox-session seatd ok")

  if mode == "terminal" {
    marker("waterfox-session startup terminal")
  } else if mode == "clipboard" {
    marker("waterfox-session startup clipboard")
  } else {
    marker("waterfox-session startup waterfox about:blank")
  }

  env {
    LIBSEAT_BACKEND = "seatd"
    MOZ_CRASHREPORTER_DISABLE = "1"
    MOZ_DISABLE_AUTO_SAFE_MODE = "1"
    MOZ_ENABLE_WAYLAND = "1"
    NO_AT_BRIDGE = "1"
    PATH = "/usr/local/bin:/usr/bin:/bin"
    SEATD_SOCK = "/run/seatd.sock"
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt"
    WAYLAND_DISPLAY = "wayland-0"
    WLR_BACKENDS = "drm,libinput"
    WLR_DRM_NO_ATOMIC = "1"
    WLR_LIBINPUT_NO_DEVICES = "0"
    WLR_RENDERER = "pixman"
    WLR_SCENE_DISABLE_DIRECT_SCANOUT = "1"
    WLR_SCENE_DISABLE_VISIBILITY = "1"
    XDG_RUNTIME_DIR = "/run/user/1000"
  } {
    marker("waterfox-session dwl start")
    let su_status = run.status /usr/bin/su "laputa" "--" "/usr/bin/waterfox-dwl-session" "--user" $mode > /dev/console 2> /dev/console ?

    if ! su_status.ok {
      let code = su_status.exit_code()?
      marker(f"waterfox-session su failed code=\${code}")
      return Err(SessionError.Failed("su", f"su handoff failed with exit code \${code}"))
    }
  } ?
}

proc main(mode: Str = "browser", selected: Str = "") [fs, process, time, error] {
  if mode == "--user" {
    let user_mode = if selected == "" { "browser" } else { selected }
    run_user_session(user_mode)?
    return
  }

  run_root_session(mode)?
}

main(@args)?
""",
  )?

  fs.chmod(fp"${dest}/usr/bin/waterfox-dwl-session", 0o755)?
}

proc install_clipboard_proof(dest: Path) [fs, error] {
  fs.write(
    fp"${dest}/usr/bin/waterfox-session-clipboard-proof",
    """#!/usr/local/bin/xsh --
error ClipboardProofError = Failed(message: Str)

proc marker(line: Str) [fs] {
  match fs.write(/dev/console, f"\${line}\\n") {
    Ok(_) => {}
    Err(_) => {}
  }
}

proc terminate_if_live(pid: Int) [process] {
  match process.kill(pid, signal: "TERM") {
    Ok(_) => {}
    Err(_) => {}
  }
}

proc main() [fs, process, time, error] {
  let value = "laputa-clipboard-proof"
  marker("waterfox-qemu clipboard helper start")
  let copy = spawn process.command_argv(
    /usr/bin/wl-copy,
    ["wl-copy", "--paste-once", value],
    timeout: 10s,
  )?

  time.sleep(500ms)?
  marker("waterfox-qemu clipboard copy spawned")
  let out = run.capture --text --timeout=5s /usr/bin/wl-paste ?
  terminate_if_live(copy.pid)

  match wait copy {
    Ok(_) => {}
    Err(ProcessError.Timeout {message: _}) => terminate_if_live(copy.pid)
    Err(_) => {}
  }

  let pasted = out.stdout

  if pasted.trim() != value {
    return Err(ClipboardProofError.Failed(f"wl-paste returned '\${pasted.trim()}'"))
  }

  marker("waterfox-qemu clipboard ok")
  fs.write(/run/user/1000/waterfox-clipboard-ok, "ok")?
}

main()?
""",
  )?

  fs.chmod(fp"${dest}/usr/bin/waterfox-session-clipboard-proof", 0o755)?
}

proc install_asound_conf(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/etc")?

  fs.write(
    fp"${dest}/etc/asound.conf",
    """pcm.!default {
  type plug
  slave.pcm "hw:0,0"
}

ctl.!default {
  type hw
  card 0
}
""",
  )?
}

proc install_boot_hook(dest: Path) [fs, error] {
  fs.write(
    fp"${dest}/usr/lib/init/rc.d/waterfox-dwl-session.boot",
    """#!/usr/local/bin/xsh
if fs.exists(/usr/bin/waterfox-dwl-session)? {
  let _session = process.spawn(
    process.command_argv(
      /usr/bin/waterfox-dwl-session,
      ["waterfox-dwl-session"],
      detach: true,
      new_session: true,
      ignore_hup: true,
    ),
  )?
}
""",
  )?

  fs.chmod(fp"${dest}/usr/lib/init/rc.d/waterfox-dwl-session.boot", 0o755)?
}

pure group_with_member(line: Str, user_name: Str) -> Str {
  let fields = line.split(":")

  if fields.len() < 4 {
    return line
  }

  let members = fields[3].split(",") |> where .trim() != ""

  if members.contains(user_name) {
    return line
  }

  let updated = members.push(user_name).join(",")
  return f"${fields[0]}:${fields[1]}:${fields[2]}:${updated}"
}

proc add_group_member(group_file: Path, group_name: Str, user_name: Str) [fs, error] {
  let lines = group_file.lines()?.collect()
  var output: List[Str] = []
  var found = false

  for line in lines {
    if line.starts_with(f"${group_name}:") {
      output = output.push(group_with_member(line, user_name))
      found = true
    } else {
      output = output.push(line)
    }
  }

  if ! found {
    output = output.push(f"${group_name}:x::${user_name}")
  }

  fs.write(
    group_file,
    f"""${output.join("\n")}
""",
  )?
}

export proc build(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/usr/bin")?
  fs.mkdir(fp"${dest}/usr/lib/init/rc.d")?
  install_session(dest)?
  install_clipboard_proof(dest)?
  install_asound_conf(dest)?
  install_boot_hook(dest)?
}

export proc post_install(root: Path) [fs, error] {
  let group_file = fp"${root}/etc/group"

  for group_name in ["video", "input", "seat", "audio", "tty"] {
    add_group_member(group_file, group_name, "laputa")?
  }
}
