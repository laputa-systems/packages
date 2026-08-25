export let name = "recipe-missing-aarch64-checksum"
export let package_kind = "payload"
export let ver = "1.0.0"
export let rel = "1"
export let deps = []
export let mkdeps_host = []
export let upstream_sources = [{
  source: p"files/input.txt",
  kind: "auto",
  architectures: ["aarch64"],
  checksums: [{arch: "x86_64", sha256: "abc"}],
}]
export let filetree = []
export proc build(dest: Path) [fs, error] {
  fs.mkdir(dest)?
}
