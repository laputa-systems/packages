#!/usr/local/bin/xsh
for dir in [/proc, /sys, /run, /dev] {
  dir.mkdir()?
}

let mount_proc = linux.mount("proc", /proc, fstype: "proc", options: ["nosuid", "noexec", "nodev"])
let mount_sys = linux.mount("sys", /sys, fstype: "sysfs", options: ["nosuid", "noexec", "nodev"])
let mount_run = linux.mount("run", /run, fstype: "tmpfs", options: ["mode=0755", "nosuid", "nodev"])
let mount_dev = linux.mount("dev", /dev, fstype: "devtmpfs", options: ["mode=0755", "nosuid"])

for dir in [/dev/pts, /dev/shm] {
  dir.mkdir()?
}

let proc_filesystems = fs.read_text(/proc/filesystems)?

if "devpts" in proc_filesystems {
  let mount_devpts = linux.mount(
    "devpts",
    /dev/pts,
    fstype: "devpts",
    options: ["mode=0620", "gid=5", "ptmxmode=0666", "nosuid", "noexec"],
  )

  if fs.exists(/dev/pts/ptmx)? and ! fs.exists(/dev/ptmx)? {
    match fs.symlink(p"pts/ptmx", /dev/ptmx) {
      Ok(_) => {}
      Err(_) => {}
    }
  }
}

if ! fs.exists(/dev/ptmx)? {
  let mknod_ptmx = linux.mknod(/dev/ptmx, "char", 5, 2)
}

let mount_shm = linux.mount("shm", /dev/shm, fstype: "tmpfs", options: ["mode=1777", "nosuid", "nodev"])

if ! fs.exists(/dev/fd)? {
  fs.symlink(/proc/self/fd, /dev/fd)?
}

if ! fs.exists(/dev/stdin)? {
  fs.symlink(p"fd/0", /dev/stdin)?
}

if ! fs.exists(/dev/stdout)? {
  fs.symlink(p"fd/1", /dev/stdout)?
}

if ! fs.exists(/dev/stderr)? {
  fs.symlink(p"fd/2", /dev/stderr)?
}

if fs.exists(/usr/bin/mdev)? {
  run /usr/bin/mdev -s ?
}

let mount_all_result = linux.mount_all()
let swapon_all_result = linux.swapon_all()

if fs.exists(/proc/sys/net/ipv4/conf/lo)? {
  let link_up_result = linux.link_up("lo")
}

if fs.exists(/etc/xsh-boot-epoch-ms)? {
  match fs.read_text(/etc/xsh-boot-epoch-ms)?.trim().parse_int() {
    Ok(epoch_ms) => let set_system_clock_result = linux.set_system_clock(epoch_ms)
    Err(_) => {}
  }
} else {
  match linux.hwclock() {
    Ok(epoch_ms) => let set_system_clock_result = linux.set_system_clock(epoch_ms)
    Err(_) => {}
  }
}

if fs.exists(/etc/hostname)? {
  let hostname = fs.read_text(/etc/hostname)?.trim()
  let set_hostname_result = unix.set_hostname(hostname)
}

let sysctl_result = linux.sysctl_load_dirs(
  [/run/sysctl.d, /etc/sysctl.d, /usr/lib/sysctl.d],
  fallback: /etc/sysctl.conf,
)

for hook in g"/usr/lib/init/rc.d/*.boot" {
  if hook.metadata()?.kind == "file" {
    run $hook ?
  }
}

for hook in g"/etc/rc.d/*.boot" {
  if hook.metadata()?.kind == "file" {
    run $hook ?
  }
}
