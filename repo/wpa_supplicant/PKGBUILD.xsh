use pm.make as make

export let name = "wpa_supplicant"

export let ver = "2.11"

export let rel = "5"

# Internal TLS/crypto — no openssl needed.
# The nl80211 driver unconditionally includes <netlink/genl/genl.h>, so libnl3
# headers and library are required at build and runtime.
export let deps = ["musl", "linux", "libnl3"]

export let mkdeps_host = ["xsh", "llvm-toolchain", "libnl3", "xinit"]

export let upstream_sources = [
  {
    source: p"https://w1.fi/releases/wpa_supplicant-2.11.tar.gz",
    kind: "auto",
    architectures: ["all"],
    checksums: [{arch: "all", sha256: "912ea06f74e30a8e36fbb68064d6cdff218d8d591db0fc5d75dee6c81ac7fc0a"}],
  },
  {source: p"config", kind: "auto", architectures: ["all"], checksums: [{arch: "all", sha256: "SKIP"}]},
  {source: p"service.xsh", kind: "auto", architectures: ["all"], checksums: [{arch: "all", sha256: "SKIP"}]},
  {source: p"wpa_supplicant.conf", kind: "auto", architectures: ["all"], checksums: [{arch: "all", sha256: "SKIP"}]},
]

export let filetree = [
  {path: p"etc/wpa_supplicant/wpa_supplicant.conf", kind: "file"},
  {path: p"usr/bin/wpa_cli", kind: "binary"},
  {path: p"usr/bin/wpa_passphrase", kind: "binary"},
  {path: p"usr/bin/wpa_supplicant", kind: "binary"},
  {path: p"usr/lib/xinit/services/wpa_supplicant.xsh", kind: "file"},
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
  var cflags = ["-O2", "-Wall", "-ffunction-sections", "-fdata-sections"]

  var includes = [
    "-I",
    fp"${src}/src".display(),
    "-I",
    fp"${src}/src/utils".display(),
    "-I",
    fp"${src}/wpa_supplicant".display(),
    "-I",
    "/usr/include",
  ]

  var defs = [
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

  var ldflags = ["-L", "/usr/lib", "-lnl-3", "-lnl-genl-3", "-Wl,--gc-sections"]

  # The set of .c files needed for a minimal WPA2-PSK + SAE build with internal
  # TLS/crypto.  Each entry is a path relative to the source root.
  # Source files for a minimal WPA2-PSK + SAE build.  Each entry is a path
  # relative to the source root.  The set mirrors what CONFIG_TLS=internal,
  # CONFIG_DRIVER_NL80211, CONFIG_SAE, and CONFIG_CTRL_IFACE bring in.
  # sae_pk.c is excluded (requires CONFIG_SAE_PK).  tdls.c, preauth.c,
  # peerkey.c, wpa_ft.c are excluded (require additional config).
  let shared_sources = [
    p"src/utils/os_unix.c",
    p"src/utils/eloop.c",
    p"src/utils/common.c",
    p"src/utils/config.c",
    p"src/utils/wpa_debug.c",
    p"src/utils/wpabuf.c",
    p"src/utils/bitfield.c",
    p"src/utils/ip_addr.c",
    p"src/utils/crc32.c",
    p"src/utils/edit.c",
    p"src/utils/radiotap.c",
    p"src/utils/base64.c",
    p"src/utils/json.c",
    p"src/utils/uuid.c",
    p"src/common/wpa_common.c",
    p"src/common/ctrl_iface_common.c",
    p"src/common/ptksa_cache.c",
    p"src/common/cli.c",
    p"src/common/wpa_ctrl.c",
    p"src/common/ieee802_11_common.c",
    p"src/common/hw_features_common.c",
    p"src/crypto/aes-wrap.c",
    p"src/crypto/aes-ccm.c",
    p"src/crypto/aes-ctr.c",
    p"src/crypto/aes-gcm.c",
    p"src/crypto/aes-omac1.c",
    p"src/crypto/aes-siv.c",
    p"src/crypto/aes-unwrap.c",
    p"src/crypto/crypto_internal.c",
    p"src/crypto/crypto_internal-cipher.c",
    p"src/crypto/crypto_internal-modexp.c",
    p"src/crypto/crypto_internal-rsa.c",
    p"src/crypto/dh_group5.c",
    p"src/crypto/dh_groups.c",
    p"src/crypto/md5.c",
    p"src/crypto/md5-internal.c",
    p"src/crypto/ms_funcs.c",
    p"src/crypto/sha1.c",
    p"src/crypto/sha1-internal.c",
    p"src/crypto/sha256.c",
    p"src/crypto/sha256-internal.c",
    p"src/crypto/sha384.c",
    p"src/crypto/sha384-internal.c",
    p"src/crypto/sha512.c",
    p"src/crypto/sha512-internal.c",
    p"src/crypto/sha1-prf.c",
    p"src/crypto/sha1-tlsprf.c",
    p"src/crypto/sha256-prf.c",
    p"src/crypto/sha1-pbkdf2.c",
    p"src/crypto/tls_internal.c",
    p"src/crypto/des-internal.c",
    p"src/crypto/md4-internal.c",
    p"src/crypto/random.c",
    p"src/crypto/rc4.c",
    p"src/crypto/aes-internal.c",
    p"src/crypto/aes-internal-enc.c",
    p"src/crypto/aes-internal-dec.c",
    p"src/tls/asn1.c",
    p"src/tls/bignum.c",
    p"src/tls/pkcs1.c",
    p"src/tls/pkcs5.c",
    p"src/tls/pkcs8.c",
    p"src/tls/rsa.c",
    p"src/tls/tlsv1_client.c",
    p"src/tls/tlsv1_client_read.c",
    p"src/tls/tlsv1_client_ocsp.c",
    p"src/tls/tlsv1_client_write.c",
    p"src/tls/tlsv1_common.c",
    p"src/tls/tlsv1_cred.c",
    p"src/tls/tlsv1_record.c",
    p"src/tls/tlsv1_server.c",
    p"src/tls/tlsv1_server_read.c",
    p"src/tls/tlsv1_server_write.c",
    p"src/tls/x509v3.c",
    p"src/rsn_supp/wpa.c",
    p"src/rsn_supp/wpa_ie.c",
    p"src/rsn_supp/pmksa_cache.c",
    p"src/drivers/driver_nl80211.c",
    p"src/drivers/driver_nl80211_capa.c",
    p"src/drivers/driver_nl80211_event.c",
    p"src/drivers/driver_nl80211_scan.c",
    p"src/drivers/drivers.c",
    p"src/drivers/netlink.c",
    p"src/drivers/driver_common.c",
    p"src/drivers/driver_nl80211_monitor.c",
    p"src/drivers/linux_ioctl.c",
    p"src/drivers/rfkill.c",
    p"src/l2_packet/l2_packet_linux.c",
    p"wpa_supplicant/config.c",
    p"wpa_supplicant/config_file.c",
    p"wpa_supplicant/bss.c",
    p"wpa_supplicant/bssid_ignore.c",
    p"wpa_supplicant/events.c",
    p"wpa_supplicant/notify.c",
    p"wpa_supplicant/wmm_ac.c",
    p"wpa_supplicant/rrm.c",
    p"wpa_supplicant/robust_av.c",
    p"wpa_supplicant/op_classes.c",
    p"wpa_supplicant/wpas_glue.c",
    p"wpa_supplicant/offchannel.c",
    p"wpa_supplicant/wpa_supplicant.c",
    p"wpa_supplicant/eap_register.c",
    p"wpa_supplicant/ctrl_iface.c",
    p"wpa_supplicant/ctrl_iface_unix.c",
    p"wpa_supplicant/scan.c",
  ]

  let shared = make.c_static_library({
    cc,
    triple,
    cflags,
    defs,
    includes,
    root: src,
    sources: shared_sources,
    out_dir: fp"${objs}/shared-objs",
    out: fp"${objs}/libwpa-common.a",
    deps: [],
  })

  let multi = make.c_multi_program({
    cc,
    triple,
    cflags,
    defs,
    includes,
    root: src,
    out_dir: fp"${objs}/compile",
    groups: [],
    targets: [
      {
        name: "wpa_supplicant",
        groups: [],
        sources: [p"wpa_supplicant/main.c"],
        libs: [shared.output],
        ldflags,
        out: fp"${objs}/wpa_supplicant",
        deps: shared.deps,
      },
      {
        name: "wpa_cli",
        groups: [],
        sources: [p"wpa_supplicant/wpa_cli.c"],
        libs: [shared.output],
        ldflags,
        out: fp"${objs}/wpa_cli",
        deps: shared.deps,
      },
      {
        name: "wpa_passphrase",
        groups: [],
        sources: [p"wpa_supplicant/wpa_passphrase.c"],
        libs: [shared.output],
        ldflags,
        out: fp"${objs}/wpa_passphrase",
        deps: shared.deps,
      },
    ],
  })?

  make.run_tasks(shared.tasks.extend(multi.tasks), make.jobs()?)?
  let wpa_supplicant_out = multi.outputs.get("wpa_supplicant")?
  let wpa_cli_out = multi.outputs.get("wpa_cli")?
  let passphrase_out = multi.outputs.get("wpa_passphrase")?

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
