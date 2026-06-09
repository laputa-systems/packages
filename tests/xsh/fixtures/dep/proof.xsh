error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  let db = fp"${root}/var/lib/xsh-pm/packages/dep/metadata.json"

  if ! fs.exists(db)? {
    return Err(ProofError.Failed("proof-dep", f"missing package metadata: ${db.display()}"))
  }

  print "dep ok"
}

main(@args)?
