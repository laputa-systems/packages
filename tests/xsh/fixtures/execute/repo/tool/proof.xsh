error ProofError = Failed(message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  if ! fs.exists(fp"${root}/var/lib/xsh-pm/packages/execute-tool/metadata.json")? {
    return Err(ProofError.Failed("missing execute-tool metadata"))
  }
}

main(@args)?
