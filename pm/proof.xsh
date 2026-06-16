use pm.util as pm_util

export error ProofError = Failed(kind: Str, message: Str)

export proc ensure(condition: Bool, kind: Str, message: Str) [error] {
  if ! condition {
    return Err(ProofError.Failed(kind, message))
  }
}

export proc package_metadata(root: Path, name: Str) [fs, error] {
  let db = fp"${root}/var/lib/xsh-pm/packages/${name}/metadata.json"
  ensure(fs.exists(db)?, f"proof-${name}", f"missing package metadata: ${db.display()}")?
}

export pure elf_machine_name(arch: Str) -> Str {
  if arch == "aarch64" {
    return "AArch64"
  }

  if arch == "x86_64" {
    return "X86-64"
  }

  return arch
}

export proc readelf_tool() [fs, process, env, error] -> Result[Path] {
  let host_readelf = /usr/bin/readelf
  let host_llvm_readelf = /usr/bin/llvm-readelf

  if fs.exists(host_readelf)? {
    return host_readelf
  }

  if fs.exists(host_llvm_readelf)? {
    return host_llvm_readelf
  }

  match process.which("readelf") {
    Ok(tool) => return tool
    Err(_) => {}
  }

  return process.which("llvm-readelf")?
}

export proc target_elf(root: Path, rel: Path, name: Str) [fs, process, env, error] {
  let path_value = fp"${root}/${rel}"
  ensure(fs.exists(path_value)?, f"proof-${name}", f"missing ELF: ${path_value.display()}")?
  let readelf = readelf_tool()?
  let header = run.text $readelf "-h" $path_value ?
  let arch = pm_util.target_arch()?
  ensure(header.contains(elf_machine_name(arch)), f"proof-${name}", f"${rel.display()} is not ${arch}")?
}
