use pm.make as make

export let name: Str = "wpa_supplicant"

export let ver: Str = "2.11"

export let rel: Str = "1"

# Internal TLS/crypto — no openssl needed.
# The nl80211 driver unconditionally includes <netlink/genl/genl.h>, so libnl3
# headers and library are required at build time (TODO: create libnl3 package).
export let deps: List[Str] = ["musl", "linux"]

export let mkdeps: List[Str] = ["xsh", "llvm-toolchain", "libnl3", "xinit"]

export let sources: List[Path] = [
  p"https://w1.fi/releases/wpa_supplicant-2.11.tar.gz",
  p"config",
  p"service.xsh",
  p"wpa_supplicant.conf",
]

export let checksums: List[Str] = [
  "912ea06f74e30a8e36fbb68064d6cdff218d8d591db0fc5d75dee6c81ac7fc0a",
  "SKIP",
  "SKIP",
  "SKIP",
]

export proc build(dest: Path) [fs, process, env, error] {
  let cwd = fs.cwd()?
  let tgz = fp"${cwd}/wpa_supplicant-2.11.tar.gz"

  # Extract into a src directory under dest's parent.
  let src = fp"${dest}/../src"
  let objs = fp"${dest}/../objs"

  if ! fs.exists(src)? {
    fs.mkdir(src)?
    archive.tar_extract(tgz, src, 1, "auto", true)?
  }

  fs.mkdir(objs)?
  fs.install(p"config", fp"${src}/wpa_supplicant/.config", 0o644, parents: true, overwrite: true)?
  let cc = process.which("cc")?
  let triple = f"${env.get("XSH_PM_ARCH") ?? "aarch64"}-linux-musl"

  # Flags mirror wpa_supplicant's defconfig: no IPv6, no D-Bus, no readline.
  var cflags: List[Str] = ["-O2", "-Wall"]

  var includes: List[Str] = [
    "-I",
    fp"${src}/src".display(),
    "-I",
    fp"${src}/src/utils".display(),
    "-I",
    fp"${src}/wpa_supplicant".display(),
    "-I",
    "/usr/include",
  ]

  var defs: List[Str] = [
    "-DCONFIG_CTRL_IFACE",
    "-DCONFIG_CTRL_IFACE_UNIX",
    "-DCONFIG_BACKEND_FILE",
    "-DCONFIG_DRIVER_NL80211",
    "-DCONFIG_IEEE80211W",
    "-DCONFIG_BGSCAN_SIMPLE",
    "-DCONFIG_GETRANDOM",
    "-DCONFIG_DEBUG_SYSLOG",
    "-DCONFIG_WPA_CLI_EDIT",
    "-DCONFIG_INTERNAL_LIBTOMMATH",
    "-DCONFIG_CRYPTO_INTERNAL",
    "-DCONFIG_LIBNL32",
  ]

  var ldflags: List[Str] = ["-L", "/usr/lib", "-lnl-3", "-lnl-genl-3"]

  # The set of .c files needed for a minimal WPA2-PSK + SAE build with internal
  # TLS/crypto.  Each entry is a path relative to the source root.
  # Source files for a minimal WPA2-PSK + SAE build.  Each entry is a path
  # relative to the source root.  The set mirrors what CONFIG_TLS=internal,
  # CONFIG_DRIVER_NL80211, CONFIG_SAE, and CONFIG_CTRL_IFACE bring in.
  # sae_pk.c is excluded (requires CONFIG_SAE_PK).  tdls.c, preauth.c,
  # peerkey.c, wpa_ft.c are excluded (require additional config).
  let source_files: List[Str] = [
    "src/utils/os_unix.c",
    "src/utils/eloop.c",
    "src/utils/common.c",
    "src/utils/config.c",
    "src/utils/wpa_debug.c",
    "src/utils/wpabuf.c",
    "src/utils/bitfield.c",
    "src/utils/ip_addr.c",
    "src/utils/crc32.c",
    "src/utils/edit.c",
    "src/utils/radiotap.c",
    "src/utils/base64.c",
    "src/utils/json.c",
    "src/utils/uuid.c",
    "src/common/wpa_common.c",
    "src/common/ctrl_iface_common.c",
    "src/common/defs.c",
    "src/common/ptksa_cache.c",
    "src/common/cli.c",
    "src/common/wpa_ctrl.c",
    "src/common/ieee802_11_common.c",
    "src/common/hw_features_common.c",
    "src/crypto/aes-wrap.c",
    "src/crypto/aes-ccm.c",
    "src/crypto/aes-ctr.c",
    "src/crypto/aes-gcm.c",
    "src/crypto/aes-omac1.c",
    "src/crypto/aes-siv.c",
    "src/crypto/aes-unwrap.c",
    "src/crypto/crypto_internal.c",
    "src/crypto/crypto_internal-cipher.c",
    "src/crypto/crypto_internal-modexp.c",
    "src/crypto/crypto_internal-rsa.c",
    "src/crypto/dh_group5.c",
    "src/crypto/dh_groups.c",
    "src/crypto/md5.c",
    "src/crypto/md5-internal.c",
    "src/crypto/ms_funcs.c",
    "src/crypto/sha1.c",
    "src/crypto/sha1-internal.c",
    "src/crypto/sha256.c",
    "src/crypto/sha256-internal.c",
    "src/crypto/sha384.c",
    "src/crypto/sha384-internal.c",
    "src/crypto/sha512.c",
    "src/crypto/sha512-internal.c",
    "src/crypto/sha1-prf.c",
    "src/crypto/sha1-tlsprf.c",
    "src/crypto/sha256-prf.c",
    "src/crypto/sha1-pbkdf2.c",
    "src/crypto/tls_internal.c",
    "src/crypto/des-internal.c",
    "src/crypto/md4-internal.c",
    "src/crypto/random.c",
    "src/crypto/rc4.c",
    "src/crypto/aes-internal.c",
    "src/crypto/aes-internal-enc.c",
    "src/crypto/aes-internal-dec.c",
    "src/tls/asn1.c",
    "src/tls/bignum.c",
    "src/tls/pkcs1.c",
    "src/tls/pkcs5.c",
    "src/tls/pkcs8.c",
    "src/tls/rsa.c",
    "src/tls/tls_internal.c",
    "src/tls/tlsv1_client.c",
    "src/tls/tlsv1_client_read.c",
    "src/tls/tlsv1_client_ocsp.c",
    "src/tls/tlsv1_client_write.c",
    "src/tls/tlsv1_common.c",
    "src/tls/tlsv1_cred.c",
    "src/tls/tlsv1_record.c",
    "src/tls/tlsv1_server.c",
    "src/tls/tlsv1_server_read.c",
    "src/tls/tlsv1_server_write.c",
    "src/tls/x509v3.c",
    "src/rsn_supp/wpa.c",
    "src/rsn_supp/wpa_ie.c",
    "src/rsn_supp/pmksa_cache.c",
    "src/drivers/driver_nl80211.c",
    "src/drivers/driver_nl80211_capa.c",
    "src/drivers/driver_nl80211_event.c",
    "src/drivers/driver_nl80211_scan.c",
    "src/drivers/drivers.c",
    "src/drivers/netlink.c",
    "src/drivers/driver_common.c",
    "src/drivers/driver_nl80211_monitor.c",
    "src/drivers/linux_ioctl.c",
    "src/drivers/rfkill.c",
    "src/l2_packet/l2_packet_linux.c",
    "wpa_supplicant/config.c",
    "wpa_supplicant/config_file.c",
    "wpa_supplicant/bss.c",
    "wpa_supplicant/blacklist.c",
    "wpa_supplicant/bssid_ignore.c",
    "wpa_supplicant/events.c",
    "wpa_supplicant/notify.c",
    "wpa_supplicant/wmm_ac.c",
    "wpa_supplicant/rrm.c",
    "wpa_supplicant/robust_av.c",
    "wpa_supplicant/op_classes.c",
    "wpa_supplicant/wpas_glue.c",
    "wpa_supplicant/offchannel.c",
    "wpa_supplicant/wpa_supplicant.c",
    "wpa_supplicant/main.c",
    "wpa_supplicant/wpa_cli.c",
    "wpa_supplicant/wpa_passphrase.c",
    "wpa_supplicant/eap_register.c",
    "wpa_supplicant/ctrl_iface.c",
    "wpa_supplicant/ctrl_iface_unix.c",
    "wpa_supplicant/scan.c",
  ]

  # Build .o tasks.  Separate into shared objects (no main), wpa_cli objects,
  # and wpa_passphrase objects.  Each binary gets shared + its own main.
  var shared_objs: List[Path] = []
  var supp_main: List[Path] = []
  var wpa_cli_objs: List[Path] = []
  var passphrase_objs: List[Path] = []
  var all_tasks: List[Record] = []

  for src_path in source_files {
    let full_src = fp"${src}/${src_path}"

    # Use the full source path (with / replaced by _) to avoid name collisions
    # between e.g. src/utils/config.c and wpa_supplicant/config.c.
    let obj_name = fp"${src_path}".display().replace("/", "_").replace(".c", ".o")
    let out = fp"${objs}/${obj_name}"
    continue unless fs.exists(full_src)?
    let task = make.compile_c_task(cc, triple, cflags, defs, includes, full_src, out)
    all_tasks = all_tasks.push(task)

    if src_path.contains("wpa_cli") {
      wpa_cli_objs = wpa_cli_objs.push(out)
    } else if src_path.contains("wpa_passphrase") {
      passphrase_objs = passphrase_objs.push(out)
    } else if src_path.ends_with("main.c") {
      supp_main = supp_main.push(out)
    } else {
      shared_objs = shared_objs.push(out)
    }
  }

  # Link each binary with shared objects + its own main.
  let wpa_supplicant_out = fp"${objs}/wpa_supplicant"
  let wpa_cli_out = fp"${objs}/wpa_cli"
  let passphrase_out = fp"${objs}/wpa_passphrase"
  let wpa_all = shared_objs.extend(supp_main)
  let cli_all = shared_objs.extend(wpa_cli_objs)
  let pass_all = shared_objs.extend(passphrase_objs)
  let compile_names = [task.name for task in all_tasks]

  all_tasks = all_tasks.push(
    make.link_executable_task(cc, triple, wpa_all, [], ldflags, wpa_supplicant_out, compile_names),
  )

  all_tasks = all_tasks.push(make.link_executable_task(cc, triple, cli_all, [], ldflags, wpa_cli_out, compile_names))

  all_tasks = all_tasks.push(
    make.link_executable_task(cc, triple, pass_all, [], ldflags, passphrase_out, compile_names),
  )

  make.run_tasks(all_tasks, make.jobs()?)?

  # Install under /usr/bin: baselayout symlinks /usr/sbin -> bin so
  # installing to /usr/sbin would fail proof extraction with "symlink escape".
  fs.install(wpa_supplicant_out, fp"${dest}/usr/bin/wpa_supplicant", 0o755, parents: true, overwrite: true)?
  fs.install(wpa_cli_out, fp"${dest}/usr/bin/wpa_cli", 0o755, parents: true, overwrite: true)?
  fs.install(passphrase_out, fp"${dest}/usr/bin/wpa_passphrase", 0o755, parents: true, overwrite: true)?

  fs.install(
    p"service.xsh",
    fp"${dest}/usr/lib/xinit/services/wpa_supplicant.xsh",
    0o644,
    parents: true,
    overwrite: true,
  )?

  fs.mkdir(fp"${dest}/etc/wpa_supplicant")?

  fs.install(
    p"wpa_supplicant.conf",
    fp"${dest}/etc/wpa_supplicant/wpa_supplicant.conf",
    0o600,
    parents: true,
    overwrite: true,
  )?
}
