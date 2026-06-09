error ProofError = Failed(kind: Str, message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  let cat = fp"${root}/usr/bin/cat"

  if ! fs.exists(cat)? {
    return Err(ProofError.Failed("proof-world-pm", f"missing cat link: ${cat.display()}"))
  }

  print "world-pm ok"
}

main(@args)?
