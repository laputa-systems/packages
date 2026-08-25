export let name = "recipe-invalid-file-kind"
export let package_kind = "payload"
export let ver = "1.0.0"
export let rel = "1"
export let deps = []
export let mkdeps_host = []
export let upstream_sources = []
export let filetree = [{path: p"usr/bin/example", kind: "invalid"}]
export proc build(dest: Path) [fs, error] {
  fs.mkdir(dest)?
}
