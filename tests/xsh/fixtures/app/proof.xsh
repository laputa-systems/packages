error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  let db = fp"${root}/var/lib/xsh-pm/packages/app/metadata.json"

  if ! fs.exists(db)? {
    return Err(ProofError.Failed("proof-app", f"missing package metadata: ${db.display()}"))
  }

  print "app ok"
}

main(@args)?
