export let name = "xinit"

export let ver = "release-f9034b48f96f49f42914498cd7bbe8a080b945b3"

export let rel = "7"

export let deps = ["xsh"]

export let mkdeps = []

export let sources = [p"https://github.com/laputa-systems/xinit/raw/c6af71070559d01a81ee88d3c5a4afb5c54b7f16/xinit.xsh"]

export let checksums = ["9f684b76166558872217adebca6d391b608d34dcb83ab87bf75748e6a8105f9d"]

export let checksums_aarch64 = [
  "9f684b76166558872217adebca6d391b608d34dcb83ab87bf75748e6a8105f9d",
]

export let checksums_x86_64 = [
  "9f684b76166558872217adebca6d391b608d34dcb83ab87bf75748e6a8105f9d",
]

export let nostrip = true

export proc build(dest: Path) [fs, error] {
  let xinit = fp"${dest}/usr/bin/xinit"
  fs.install(p"xinit.xsh", xinit, 0o755, parents: true, overwrite: true)?
  fs.write(xinit, fs.read_text(xinit)?.replace("#!/usr/local/bin/xsh", "#!/bin/xsh"))?
  fs.chmod(xinit, 0o755)?
  fs.symlink(p"xinit", fp"${dest}/usr/bin/init")?
  fs.symlink(p"usr/bin/xinit", fp"${dest}/init")?
}

export let filetree = [
  {path: p"init", kind: "symlink"},
  {path: p"usr/bin/init", kind: "symlink"},
  {path: p"usr/bin/xinit", kind: "file"},
]
