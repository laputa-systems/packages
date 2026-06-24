use pm.proof

proc main(root: Path = /rootfs) [fs, process, error] {
  proof.package_metadata(root, "wpa_supplicant")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/wpa_supplicant")?, "wpa_supplicant", "missing wpa_supplicant binary")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/wpa_cli")?, "wpa_supplicant", "missing wpa_cli binary")?
  proof.ensure(fs.exists(fp"${root}/usr/bin/wpa_passphrase")?, "wpa_supplicant", "missing wpa_passphrase binary")?
  proof.ensure(fs.exists(fp"${root}/usr/lib/xinit/services/wpa_supplicant.xsh")?, "wpa_supplicant", "missing service file")?
  proof.ensure(fs.exists(fp"${root}/etc/wpa_supplicant/wpa_supplicant.conf")?, "wpa_supplicant", "missing default config")?

  # Smoke test: binary should at least print help.
  let status = process.run(process.command_argv(
    fp"${root}/usr/bin/wpa_supplicant",
    ["wpa_supplicant", "--help"],
    /,
    {},
  ))?

  if status.exited() and status.exit_code()? != 0 {
    return Err(proof.ProofError.Failed("wpa_supplicant", "--help exited non-zero"))
  }

  print "wpa_supplicant ok"
}

main(@args)?
