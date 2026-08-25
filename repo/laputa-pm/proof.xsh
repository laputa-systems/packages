##! XSH module `proof` package and build operations.
error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  let db = fp"${root}/var/lib/xsh-pm/packages/laputa-pm/metadata.json"
  let pm = fp"${root}/usr/bin/pm"

  if ! fs.exists(db)? {
    return Err(ProofError.Failed("proof-laputa-pm", f"missing package metadata: ${db.display()}"))
  }

  if ! fs.exists(pm)? {
    return Err(ProofError.Failed("proof-laputa-pm", f"missing pm wrapper: ${pm.display()}"))
  }

  print "laputa-pm ok"
}

main(@args)?
