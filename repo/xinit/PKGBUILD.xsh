export let name: Str = "xinit"

export let ver: Str = "release-f9034b48f96f49f42914498cd7bbe8a080b945b3"

export let rel: Str = "5"

export let deps: List[Str] = ["xsh"]

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://github.com/laputa-systems/xinit/raw/c6af71070559d01a81ee88d3c5a4afb5c54b7f16/xinit.xsh",
]

export let checksums: List[Str] = ["9f684b76166558872217adebca6d391b608d34dcb83ab87bf75748e6a8105f9d"]

export let checksums_aarch64 = ["9f684b76166558872217adebca6d391b608d34dcb83ab87bf75748e6a8105f9d"]

export let checksums_x86_64 = ["9f684b76166558872217adebca6d391b608d34dcb83ab87bf75748e6a8105f9d"]

export let nostrip: Bool = true

export proc build(dest: Path) [fs, error] {
  fs.install(p"xinit.xsh", fp"${dest}/usr/bin/xinit", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"xinit", fp"${dest}/usr/bin/init")?
  fs.symlink(p"usr/bin/xinit", fp"${dest}/init")?
}
