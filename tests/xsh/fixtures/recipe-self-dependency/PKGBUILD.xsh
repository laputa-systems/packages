export let name = "recipe-self-dependency"
export let package_kind = "payload"
export let ver = "1.0.0"
export let rel = "1"
export let deps = ["recipe-self-dependency"]
export let mkdeps_host = []
export let upstream_sources = []
export let filetree = []
export proc build(dest: Path) [fs, error] {
  fs.mkdir(dest)?
}
