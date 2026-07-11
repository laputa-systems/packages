export let name = "remote-app"

export let ver = "1.0.0"

export let rel = "1"

export let deps = []

export let mkdeps = []

export let sources = [p"files/payload.txt"]

export let checksums = ["00c019dc6f8b7f8ca3202a0dc05b2ed1f62294845e90555771473928e8cfb959"]

export let filetree = [{path: p"usr/share/remote-app/payload.txt", kind: "file"}]

export proc build(dest: Path) [fs, error] -> Result[Unit] {
  let target = fp"${dest}/usr/share/remote-app/payload.txt"
  fs.mkdir(target.parent)?
  fs.install(p"payload.txt", target, 0o644)?
}
