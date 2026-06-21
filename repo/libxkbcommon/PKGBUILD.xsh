use pm.util as pm_util

export let name: Str = "libxkbcommon"
export let ver: Str = "1.11.0"
export let rel: Str = "2"
export let deps: List[Str] = ["musl", "xkeyboard-config"]
export let mkdeps: List[Str] = ["llvm-toolchain", "muon", "pkgconf", "xkeyboard-config", "bison"]
export let sources: List[Path] = [
  p"https://github.com/xkbcommon/libxkbcommon/archive/xkbcommon-VERSION.tar.gz",
  p"files/parser.c => generated",
  p"files/parser.h => generated",
]
export let checksums: List[Str] = [
  "78a6b14f16e9a55025978c252e53ce9e16a02bfdb929550b9a0db5af87db7e02",
  "daf7f1f7aa43c171101d156f65921fede315e31cf9342a6434e98b48ce1eb06c",
  "13e7772276a17d4a803c5591bef231f268ae60bd4b9dbfa14fb7b80c955da3d4",
]

export proc build(dest: Path) [fs, process, env, error] {
  fs.install(p"generated/parser.c", p"src/xkbcomp/parser.c", 0o644, parents: true, overwrite: true)?
  fs.install(p"generated/parser.h", p"src/xkbcomp/parser.h", 0o644, parents: true, overwrite: true)?
  let jobs_flag = f"-j${cpu.count()}"

  run "muon" "setup" "-Dprefix=/usr" "-Dlibdir=lib" "-Ddefault_library=shared" "-Dxkb-config-root=/usr/share/X11/xkb" "-Denable-docs=false" "-Denable-tools=false" "-Denable-x11=false" "-Denable-wayland=false" "-Denable-xkbregistry=false" "-Denable-bash-completion=false" "build" ?
  run "muon" "-C" "build" samu "-j1" "libxkbcommon.so.0.11.0" ?
  env { DESTDIR = dest.display() } { run "muon" "-C" "build" install ? } ?
  fs.remove(fp"${dest}/usr/share/bash-completion", missing_ok: true)?
}
