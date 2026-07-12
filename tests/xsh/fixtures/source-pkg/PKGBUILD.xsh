export let name = "source-pkg"

export let ver = "1.0.0"

export let rel = "1"

export let deps = []

export let mkdeps_host = []

export let upstream_sources = [
  {source: p"files/data.txt", kind: "auto", architectures: ["all"], checksums: [{arch: "all", sha256: "0000000000000000000000000000000000000000000000000000000000000000"}]}
]



export let filetree = [{path: p"usr/share/source-pkg/data.txt", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/share/source-pkg/data.txt"
  fs.mkdir(target.parent)?
  fs.install(p"data.txt", target, 0o644)?
}
