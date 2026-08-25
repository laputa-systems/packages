error ProofError = Failed(kind: Str, message: Str)

proc ensure_file(path_value: Path, label: Str) [fs, error] {
  if ! fs.exists(path_value)? {
    return Err(ProofError.Failed("proof-linux", f"missing ${label}: ${path_value.display()}"))?
  }

  let meta = fs.metadata(path_value)?

  if meta.size <= 0 {
    return Err(ProofError.Failed("proof-linux", f"empty ${label}: ${path_value.display()}"))?
  }
}

proc ensure_config(config_path: Path, key: Str, label: Str) [fs, error] {
  if ! config_path.exists()? {
    return Err(ProofError.Failed("proof-linux", f"missing config for ${label} check: ${config_path.display()}"))?
  }

  for raw in config_path.read_text()?.split("\n") {
    let line = raw.trim()

    if line == f"${key}=y" {
      return
    }
  }

  return Err(ProofError.Failed("proof-linux", f"${label}: expected ${key}=y not found in ${config_path.display()}"))?
}

proc ensure_x86_bzimage(image_path: Path) [fs, error] {
  let meta = fs.metadata(image_path)?

  if meta.size < 518 {
    return Err(ProofError.Failed("proof-linux", f"x86_64 boot image is too small: ${image_path.display()}"))?
  }

  let image = image_path.read_bytes()?
  let mz = bytes.from_text("MZ")
  let hdrs = bytes.from_text("HdrS")

  if image.slice(offset: 0, length: 2) != mz {
    return Err(
      ProofError.Failed(
        "proof-linux",
        f"x86_64 boot image is not a bzImage: missing MZ header in ${image_path.display()}",
      ),
    )?
  }

  if image.slice(offset: 514, length: 4) != hdrs {
    return Err(
      ProofError.Failed(
        "proof-linux",
        f"x86_64 boot image is not a bzImage: missing HdrS setup header in ${image_path.display()}",
      ),
    )?
  }
}

proc main(rootfs: Path = /rootfs) [fs, env, error] {
  ensure_file(fp"${rootfs}/boot/vmlinuz", "kernel image")?
  ensure_file(fp"${rootfs}/usr/share/linux/config-7.0.5", "kernel config")?
  ensure_file(fp"${rootfs}/usr/include/linux/version.h", "linux version header")?
  ensure_file(fp"${rootfs}/usr/include/asm/unistd.h", "arch uapi header")?
  let config_path = fp"${rootfs}/usr/share/linux/config-7.0.5"
  let os = system.uname()?
  let host_machine = os.machine
  let proof_arch = env.get("XSH_PM_TARGET_ARCH") ?? env.get("XSH_PM_ARCH") ?? host_machine

  if proof_arch == "x86_64" or proof_arch == "amd64" {
    ensure_config(config_path, "CONFIG_X86_64", "x86_64 arch check")?
    ensure_x86_bzimage(fp"${rootfs}/boot/vmlinuz")?
  } else if proof_arch == "aarch64" or proof_arch == "arm64" {
    ensure_config(config_path, "CONFIG_ARM64", "arm64 arch check")?
  } else {
    return Err(ProofError.Failed("proof-linux", f"unsupported proof arch: ${proof_arch}"))?
  }

  print "linux ok: vmlinuz and uapi headers"
}

main(@args)?
