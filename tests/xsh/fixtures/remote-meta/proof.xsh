error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  let db = fp"${root}/var/lib/xsh-pm/packages/remote-meta/metadata.json"

  if ! fs.exists(db)? {
    return Err(ProofError.Failed("proof-remote-meta", f"missing package metadata: ${db.display()}"))
  }

  print "remote-meta ok"
}

main(@args)?
