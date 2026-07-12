export let name = "waterfox-bin"

export let ver = "140.11.0esr"

export let rel = "10"

export let deps = ["musl", "ca-certificates"]

export let mkdeps_host = []

export let nostrip = true

export let upstream_sources = [
  {
    source: p"https://github.com/joshuarli/waterfox-musl-squashed/releases/download/initial-arm64-hermetic/waterfox-140.11.0esr.en-US.linux-musl-aarch64.stage1-minwayland-release-arm64.1.tar.xz => waterfox",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "f22e9a92b15f26a1b805d85a7a1418ede89d8c6116b65b5af1d5600771ae89f2",
      },
    ],
  },
  {
    source: p"files/waterfox-elf-scan.xsh",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "6c422f8fff25ea1e9c0be524064bc3f95a6b47abcbca5c2c3dee02c85c2bd0c1",
      },
    ],
  },
  {
    source: p"files/waterfox-private-needed.xsh",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "f096fda5370eb78b4e14fe5d535ab780fb3d0c61dd703856c59683264dfb550e",
      },
    ],
  },
  {
    source: p"files/waterfox-allowed-external.sonames",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "2190dcebd0a465fb2ed33caec377f8f9e3a0e6ab60b715e7cfa0e5bf179ef6ea",
      },
    ],
  },
]

error WaterfoxPackageError = Package(message: Str)

let reject_sonames = "libX11|libX11-xcb|libxcb|libxcb-shm|libxcb-composite|libxcb-dri3|libxcb-ewmh|libxcb-icccm|libxcb-present|libxcb-randr|libxcb-render|libxcb-shape|libxcb-sync|libxcb-xfixes|libXcomposite|libXdamage|libXext|libXfixes|libXi|libXinerama|libXrandr|libXrender|libXcursor|libxkbfile|libXt|libSM|libICE|libGLX|libgtk|libgdk|libglib|libgio|libgobject|libpango|libatk|libatspi|libpipewire|libpulse|libdbus|libnotify|libsecret|libspeechd|libcups|libva|libvulkan|libmimalloc\\.so"

type ElfScanModule = module {
  export proc scan_waterfox_elf(root: Path, allowed_external_sonames: Path, private_library_root: Path, reject_pattern: Str) [fs, error] -> Result[Record]
}

type PrivateNeededModule = module {
  export proc verify_private_needed(root: Path, allowed_external_sonames: Path, private_library_root: Path) [fs, error] -> Result[Record]
}

export let filetree = [
  {
    path: p"opt/waterfox/application.ini",
    kind: "file",
  },
  {
    path: p"opt/waterfox/browser/omni.ja",
    kind: "file",
  },
  {
    path: p"opt/waterfox/defaults/pref/channel-prefs.js",
    kind: "file",
  },
  {
    path: p"opt/waterfox/defaults/pref/laputa-policy.js",
    kind: "file",
  },
  {
    path: p"opt/waterfox/dependentlibs.list",
    kind: "file",
  },
  {
    path: p"opt/waterfox/gmp-clearkey/0.1/libclearkey.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/gmp-clearkey/0.1/manifest.json",
    kind: "file",
  },
  {
    path: p"opt/waterfox/libfreeblpriv3.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/libgkcodecs.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/liblgpllibs.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/libmozavcodec.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/libmozavutil.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/libmozsandbox.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/libmozsqlite3.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/libnspr4.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/libnss3.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/libnssutil3.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/libplc4.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/libplds4.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/libsmime3.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/libsoftokn3.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/libssl3.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/libxul.so",
    kind: "binary",
  },
  {
    path: p"opt/waterfox/omni.ja",
    kind: "file",
  },
  {
    path: p"opt/waterfox/platform.ini",
    kind: "file",
  },
  {
    path: p"opt/waterfox/precomplete",
    kind: "file",
  },
  {
    path: p"opt/waterfox/removed-files",
    kind: "file",
  },
  {
    path: p"opt/waterfox/waterfox",
    kind: "file",
  },
  {
    path: p"opt/waterfox/waterfox-bin",
    kind: "binary",
  },
  {
    path: p"usr/bin/waterfox",
    kind: "file",
  },
]

proc install_policy_prefs(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/opt/waterfox/defaults/pref")?

  fs.write(
    fp"${dest}/opt/waterfox/defaults/pref/laputa-policy.js",
    """pref("app.update.enabled", false);
pref("app.update.auto", false);
pref("browser.aboutwelcome.enabled", false);
pref("browser.shell.checkDefaultBrowser", false);
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("toolkit.telemetry.enabled", false);
pref("breakpad.reportURL", "");
""",
  )?
}

proc install_wrapper(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/usr/bin")?

  fs.write(
    fp"${dest}/usr/bin/waterfox",
    """#!/bin/xsh
proc main(...argv: List[Str]) [process, error] {
  env {
    LD_LIBRARY_PATH = "/opt/waterfox"
    MOZ_CRASHREPORTER_DISABLE = "1"
    MOZ_DISABLE_AUTO_SAFE_MODE = "1"
    MOZ_ENABLE_WAYLAND = "1"
    NO_AT_BRIDGE = "1"
  } {
    run /opt/waterfox/waterfox-bin @argv ?
  } ?
}

main(@args)?
""",
  )?

  fs.chmod(fp"${dest}/usr/bin/waterfox", 0o755)?
}

export proc build(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/opt")?
  let copied = fs.copy_tree(p"waterfox", fp"${dest}/opt/waterfox", parents: true, overwrite: true)?
  install_wrapper(dest)?
  install_policy_prefs(dest)?

  if ! fs.executable(fp"${dest}/opt/waterfox/waterfox-bin")? {
    return Err(WaterfoxPackageError.Package("/opt/waterfox/waterfox-bin is missing or not executable"))
  }

  let scanner = module.load(p"waterfox-elf-scan.xsh")?.require(ElfScanModule)?

  let scan_report = scanner.scan_waterfox_elf(
    dest,
    p"waterfox-allowed-external.sonames",
    fp"${dest}/opt/waterfox",
    reject_sonames,
  )?

  let private_needed = module.load(p"waterfox-private-needed.xsh")?.require(PrivateNeededModule)?

  let private_needed_report = private_needed.verify_private_needed(
    dest,
    p"waterfox-allowed-external.sonames",
    fp"${dest}/opt/waterfox",
  )?

  let _ = {copied, scan_report, private_needed_report}
}
