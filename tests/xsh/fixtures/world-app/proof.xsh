error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  let dep = fp"${root}/usr/share/world-lib.txt"
  let payload = fp"${root}/usr/share/world-app.txt"

  if ! fs.exists(dep)? {
    return Err(ProofError.Failed("proof-world-app", f"missing rebuilt dependency: ${dep.display()}"))
  }

  if ! fs.exists(payload)? {
    return Err(ProofError.Failed("proof-world-app", f"missing payload: ${payload.display()}"))
  }

  print "world-app ok"
}

main(@args)?
