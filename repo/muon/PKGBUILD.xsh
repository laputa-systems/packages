use pm.util as pm_util

export let name = "muon"

export let ver = "0.5.0"

export let rel = "8"

export let deps = ["musl"]

export let mkdeps_host = ["llvm-toolchain", "samurai"]

export let upstream_sources = [
  {
    source: p"https://github.com/muon-build/muon/archive/refs/tags/VERSION.tar.gz",
    kind: "auto",
    architectures: ["all"],
    checksums: [{arch: "all", sha256: "565c1b6e1e58f7e90d8813fda0e2102df69fb493ddab4cf6a84ce3647466bee5"}],
  },
]

export let filetree = [{path: p"usr/bin/muon", kind: "binary"}]

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let cross_build = pm_util.build_arch()? != pm_util.target_arch()?
  var bootstrap_cc = cc
  var host_ld_library_path = ""

  if cross_build {
    let build_root = fp"${env.get("XSH_PM_BUILD_ROOT") ?? ""}"
    bootstrap_cc = fp"${build_root}/usr/bin/cc"
    host_ld_library_path = f"${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib"
  }

  fs.mkdir(p"build")?

  if cross_build {
    env {
      LD_LIBRARY_PATH = host_ld_library_path
    } {
      run $bootstrap_cc "-std=c99" "-O2" "-Iinclude" "src/amalgam.c" "-o" "build/muon-bootstrap" ?
    } ?
  } else {
    run $bootstrap_cc "-std=c99" "-O2" "-Iinclude" "src/amalgam.c" "-o" "build/muon-bootstrap" ?
  }

  let setup_args = [
    "setup",
    "-Dbuildtype=debug",
    "-Dlibcurl=disabled",
    "-Dlibarchive=disabled",
    "-Dlibpkgconf=disabled",
    "-Dsamurai=enabled",
    "-Dtracy=disabled",
    "-Dman-pages=disabled",
    "-Dmeson-docs=disabled",
    "-Dmeson-tests=disabled",
    "-Dwebsite=disabled",
    "build",
  ]

  if cross_build {
    env {
      LD_LIBRARY_PATH = host_ld_library_path
    } {
      run "build/muon-bootstrap" ${setup_args} ?
      let build_ninja = p"build/build.ninja"
      var patched_ninja = build_ninja.read_text()?

      patched_ninja = patched_ninja.replace(
        """rule muon_build_c_linker
 command = cc""",
        f"""rule muon_build_c_linker
 command = ${bootstrap_cc}""",
      )

      patched_ninja = patched_ninja.replace(
        """rule muon_build_c_compiler
 command = cc""",
        f"""rule muon_build_c_compiler
 command = ${bootstrap_cc}""",
      )

      fs.write(build_ninja, patched_ninja)?
      run "build/muon-bootstrap" "-C" "build" "samu" ?
    } ?
  } else {
    run "build/muon-bootstrap" ${setup_args} ?
    run "build/muon-bootstrap" "-C" "build" "samu" ?
  }

  fs.install(p"build/muon", fp"${dest}/usr/bin/muon", 0o755, parents: true, overwrite: true)?
}
