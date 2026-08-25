export let name = "recipe-remote-skip"
export let package_kind = "payload"
export let ver = "1.0.0"
export let rel = "1"
export let deps = []
export let mkdeps_host = []
export let upstream_sources = [{
  source: p"https://example.invalid/source.tar.gz",
  kind: "auto",
  architectures: ["all"],
  checksums: [{arch: "all", sha256: "SKIP"}],
}]
export let filetree = []
export proc build(dest: Path) [fs, error] {
  fs.mkdir(dest)?
}
