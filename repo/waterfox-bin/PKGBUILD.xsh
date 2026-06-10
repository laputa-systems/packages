export let name: Str = "waterfox-bin"

export let ver: Str = "140.11.0esr"

export let rel: Str = "3"

export let deps: List[Str] = ["musl", "ca-certificates"]

export let mkdeps: List[Str] = []

export let nostrip: Bool = true

export let sources: List[Path] = [
  p"https://github.com/joshuarli/waterfox-musl-squashed/releases/download/initial-arm64-hermetic/waterfox-140.11.0esr.en-US.linux-musl-aarch64.stage1-minwayland-release-arm64.1.tar.xz => waterfox",
  p"files/waterfox-elf-scan.xsh",
  p"files/waterfox-private-needed.xsh",
  p"files/waterfox-allowed-external.sonames",
]

export let checksums: List[Str] = [
  "f22e9a92b15f26a1b805d85a7a1418ede89d8c6116b65b5af1d5600771ae89f2",
  "f9d5e2f2f04edae4763df666b86b2b46135a4dac1995880c34304d4e14383f1f",
  "2299e33aa0b04dc20750e3b915922318ebc8f9fd569f0b3cea021114ab948324",
  "2190dcebd0a465fb2ed33caec377f8f9e3a0e6ab60b715e7cfa0e5bf179ef6ea",
]

error WaterfoxPackageError = Package(message: Str)

let reject_sonames = "libX11|libX11-xcb|libxcb|libxcb-shm|libxcb-composite|libxcb-dri3|libxcb-ewmh|libxcb-icccm|libxcb-present|libxcb-randr|libxcb-render|libxcb-shape|libxcb-sync|libxcb-xfixes|libXcomposite|libXdamage|libXext|libXfixes|libXi|libXinerama|libXrandr|libXrender|libXcursor|libxkbfile|libXt|libSM|libICE|libGLX|libgtk|libgdk|libglib|libgio|libgobject|libpango|libatk|libatspi|libpipewire|libpulse|libdbus|libnotify|libsecret|libspeechd|libcups|libva|libvulkan|libmimalloc\\.so"

type ElfScanModule = module {
  export proc scan_waterfox_elf(
    root: Path,
    allowed_external_sonames: Path,
    private_library_root: Path,
    reject_pattern: Str,
  ) [fs, error] -> Result[Record]
}

type PrivateNeededModule = module {
  export proc verify_private_needed(
    root: Path,
    allowed_external_sonames: Path,
    private_library_root: Path,
  ) [fs, error] -> Result[Record]
}

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
    """#!/usr/local/bin/xsh --
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
  let scan_report = scanner.scan_waterfox_elf(dest, p"waterfox-allowed-external.sonames", fp"${dest}/opt/waterfox", reject_sonames)?
  let private_needed = module.load(p"waterfox-private-needed.xsh")?.require(PrivateNeededModule)?

  let private_needed_report = private_needed.verify_private_needed(
    dest,
    p"waterfox-allowed-external.sonames",
    fp"${dest}/opt/waterfox",
  )?
  let _ = {copied, scan_report, private_needed_report}
}
