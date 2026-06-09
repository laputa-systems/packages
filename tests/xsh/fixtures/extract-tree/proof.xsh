error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  let db = fp"${root}/var/lib/xsh-pm/packages/extract-tree/metadata.json"

  if ! fs.exists(db)? {
    return Err(ProofError.Failed("proof-extract-tree", f"missing package metadata: ${db.display()}"))
  }

  print "extract-tree ok"
}

main(@args)?
