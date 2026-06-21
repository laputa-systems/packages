use pm.util as pm_util

export let name: Str = "libdisplay-info"
export let ver: Str = "0.3.0"
export let rel: Str = "3"
export let deps: List[Str] = ["musl", "hwdata"]
export let mkdeps: List[Str] = ["llvm-toolchain", "muon", "pkgconf", "hwdata", "bison"]
export let sources: List[Path] = [
  p"https://gitlab.freedesktop.org/emersion/libdisplay-info/-/releases/VERSION/downloads/libdisplay-info-VERSION.tar.xz",
]
export let checksums: List[Str] = ["71d5f2df32f6988765d5ff946c2332a4950762f0a594918ca13f965b0771640e"]

export proc build(dest: Path) [fs, process, env, error] {
  let jobs_flag = f"-j${cpu.count()}"

  run "muon" "setup" "-Dprefix=/usr" "-Dlibdir=lib" "-Ddefault_library=shared" "-Ddi-edid-decode=disabled" "-Dtest=false" "build" ?
  run "muon" "-C" "build" samu $jobs_flag ?
  env { DESTDIR = dest.display() } { run "muon" "-C" "build" install ? } ?
}
