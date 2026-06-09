error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  let db = fp"${root}/var/lib/xsh-pm/packages/remote-app/metadata.json"

  if ! fs.exists(db)? {
    return Err(ProofError.Failed("proof-remote-app", f"missing package metadata: ${db.display()}"))
  }

  print "remote-app ok"
}

main(@args)?
