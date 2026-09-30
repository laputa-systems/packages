error ProofError = Failed(message: Str)

proc main(root = /rootfs) [fs, error] {
  guard fs.exists(fp"${root}/var/lib/xsh-pm/packages/execute-tool/metadata.json")? else {
    return Err(ProofError.Failed("missing execute-tool metadata"))
  }
}

main(@args)?
