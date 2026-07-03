use kbuild

proc ensure_file(path_value: Path, label: Str) [fs, error] {
  if ! fs.exists(path_value)? {
    return Err(ScriptError.Failed("proof-linux", f"missing ${label}: ${path_value.display()}"))?
  }

  let meta = fs.metadata(path_value)?

  if meta.size <= 0 {
    return Err(ScriptError.Failed("proof-linux", f"empty ${label}: ${path_value.display()}"))?
  }
}

proc ensure_config(config_path: Path, key: Str, label: Str) [fs, error] {
  if ! config_path.exists()? {
    return Err(ScriptError.Failed("proof-linux", f"missing config for ${label} check: ${config_path.display()}"))?
  }

  for raw in config_path.read_text()?.split("\n") {
    let line = raw.trim()

    if line == f"${key}=y" {
      return
    }
  }

  return Err(ScriptError.Failed("proof-linux", f"${label}: expected ${key}=y not found in ${config_path.display()}"))?
}

proc ensure_x86_bzimage(image_path: Path) [fs, error] {
  let meta = fs.metadata(image_path)?

  if meta.size < 518 {
    return Err(ScriptError.Failed("proof-linux", f"x86_64 boot image is too small: ${image_path.display()}"))?
  }

  let image = image_path.read_bytes()?
  let mz = bytes.from_text("MZ")
  let hdrs = bytes.from_text("HdrS")

  if image.slice(offset: 0, length: 2) != mz {
    return Err(
      ScriptError.Failed(
        "proof-linux",
        f"x86_64 boot image is not a bzImage: missing MZ header in ${image_path.display()}",
      ),
    )?
  }

  if image.slice(offset: 514, length: 4) != hdrs {
    return Err(
      ScriptError.Failed(
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
    ensure_config(config_path, "CONFIG_DRM", "x86_64 DRM core")?
    ensure_config(config_path, "CONFIG_DRM_KMS_HELPER", "x86_64 DRM KMS helper")?
    ensure_config(config_path, "CONFIG_DRM_I915", "x86_64 Intel i915 DRM")?
    ensure_config(config_path, "CONFIG_DRM_SIMPLEDRM", "x86_64 EFI/simpledrm boot display")?
    ensure_config(config_path, "CONFIG_FW_LOADER", "x86_64 firmware loader")?
    ensure_config(config_path, "CONFIG_INPUT_EVDEV", "x86_64 evdev input")?
    ensure_config(config_path, "CONFIG_I2C_HID", "x86_64 I2C HID")?
    ensure_config(config_path, "CONFIG_HID_MULTITOUCH", "x86_64 multitouch HID")?
    ensure_config(config_path, "CONFIG_ACPI_VIDEO", "x86_64 ACPI video")?
    ensure_config(config_path, "CONFIG_BACKLIGHT_CLASS_DEVICE", "x86_64 backlight")?
    ensure_config(config_path, "CONFIG_BLK_DEV_NVME", "x86_64 NVMe storage")?
    ensure_config(config_path, "CONFIG_USB_XHCI_HCD", "x86_64 USB xHCI")?
    ensure_config(config_path, "CONFIG_USB_HID", "x86_64 USB HID")?
    ensure_config(config_path, "CONFIG_SND_HDA_INTEL", "x86_64 Intel HDA audio")?
    ensure_config(config_path, "CONFIG_IWLWIFI", "x86_64 Intel Wi-Fi")?
    ensure_config(config_path, "CONFIG_IWLMVM", "x86_64 Intel MVM Wi-Fi")?
    ensure_config(config_path, "CONFIG_CFG80211", "x86_64 wireless cfg80211")?
    ensure_config(config_path, "CONFIG_MAC80211", "x86_64 wireless mac80211")?
    ensure_config(config_path, "CONFIG_DELL_LAPTOP", "x86_64 Dell laptop platform")?
    ensure_config(config_path, "CONFIG_DELL_WMI", "x86_64 Dell WMI")?
    ensure_config(config_path, "CONFIG_DELL_SMBIOS", "x86_64 Dell SMBIOS")?
  } else if proof_arch == "aarch64" or proof_arch == "arm64" {
    ensure_config(config_path, "CONFIG_ARM64", "arm64 arch check")?
  } else {
    return Err(ScriptError.Failed("proof-linux", f"unsupported proof arch: ${proof_arch}"))?
  }

  print "linux ok: vmlinuz and uapi headers"
}

main(@args)?
