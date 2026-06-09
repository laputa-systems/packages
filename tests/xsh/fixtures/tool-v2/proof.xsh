error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  let db = fp"${root}/var/lib/xsh-pm/packages/tool/metadata.json"

  if ! fs.exists(db)? {
    return Err(ProofError.Failed("proof-tool", f"missing package metadata: ${db.display()}"))
  }

  print "tool ok"
}

main(@args)?
