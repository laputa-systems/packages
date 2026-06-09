error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  let db = fp"${root}/var/lib/xsh-pm/packages/laputa-pm/metadata.json"
  let pm = fp"${root}/usr/bin/pm"
  let bin_cat = fp"${root}/bin/cat"
  let usr_bin_cat = fp"${root}/usr/bin/cat"

  if ! fs.exists(db)? {
    return Err(ProofError.Failed("proof-laputa-pm", f"missing package metadata: ${db.display()}"))
  }

  if ! fs.exists(pm)? {
    return Err(ProofError.Failed("proof-laputa-pm", f"missing pm wrapper: ${pm.display()}"))
  }

  if ! fs.exists(bin_cat)? {
    return Err(ProofError.Failed("proof-laputa-pm", f"missing core cat link: ${bin_cat.display()}"))
  }

  if ! fs.exists(usr_bin_cat)? {
    return Err(ProofError.Failed("proof-laputa-pm", f"missing core cat link: ${usr_bin_cat.display()}"))
  }

  print "laputa-pm ok"
}

main(@args)?
