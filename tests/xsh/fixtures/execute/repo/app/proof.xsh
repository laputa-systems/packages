error ProofError = Failed(message: Str)

proc main(root: Path = /rootfs) [fs, error] {
  if ! fs.exists(fp"${root}/var/lib/xsh-pm/packages/execute-app/metadata.json")? {
    return Err(ProofError.Failed("missing execute-app metadata"))
  }

  if ! fs.exists(fp"${root}/usr/share/execute-dep.txt")? {
    return Err(ProofError.Failed("runtime dependency is missing from proof root"))
  }

  if fs.exists(fp"${root}/usr/share/execute-tool.txt")? {
    return Err(ProofError.Failed("build-host dependency leaked into proof root"))
  }
}

main(@args)?
