error ProofError = Failed(message: Str)

proc main(root = /rootfs) [fs, error] {
  guard fs.exists(fp"${root}/var/lib/xsh-pm/packages/execute-dep/metadata.json")? else {
    return Err(ProofError.Failed("missing execute-dep metadata"))
  }
}

main(@args)?
