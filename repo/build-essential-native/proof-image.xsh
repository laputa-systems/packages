##! XSH module `proof-image` package and build operations.
error ScriptError = Failed(kind: Str, message: Str)

proc ensure(condition: Bool, kind: Str, message: Str) [error] {
  if ! condition {
    Err(ScriptError.Failed(kind, message))?
  }
}

proc require_tool(name: Str) [process, error] -> Result[Path] {
  process.which(name)?
}

proc require_tool_runs(tool: Path, args: List[Str]) [process, error] {
  let _ = run.text $tool @args ?
}

proc require_absent(path_value: Path, label: Str) [fs, error] {
  ensure(! fs.exists(path_value)?, "build-essential-native", f"unexpected ${label}: ${path_value.display()}")?
}

proc main() [fs, process, env, error] {
  require_absent(/etc/alpine-release, "Alpine release marker")?
  require_absent(/lib/apk, "Alpine package database")?
  require_absent(/sbin/apk, "Alpine package manager")?

  ensure(
    fs.exists(/var/lib/xsh-pm/packages/zlib/metadata.json)?,
    "build-essential-native",
    "zlib must be package-owned",
  )?

  let cc = require_tool("cc")?
  let cxx = require_tool("c++")?
  let pkg_config = require_tool("pkg-config")?
  let cmake = require_tool("cmake")?
  let samu = require_tool("samu")?
  let m4 = require_tool("m4")?
  let flex = require_tool("flex")?
  let bison = require_tool("bison")?
  let muon = require_tool("muon")?
  require_tool_runs(cc, ["--version"])?
  require_tool_runs(cxx, ["--version"])?
  require_tool_runs(pkg_config, ["--version"])?
  require_tool_runs(cmake, ["--version"])?
  require_tool_runs(samu, ["--version"])?
  require_tool_runs(m4, ["--version"])?
  require_tool_runs(flex, ["--version"])?
  require_tool_runs(bison, ["--version"])?
  require_tool_runs(muon, ["version"])?
  let os = system.uname()?
  let arch = os.machine
  let dynlinker = fp"/usr/lib/ld-musl-${arch}.so.1"
  let tmp_root = fs.tempdir()?
  defer fs.close_root(tmp_root)?
  let tmp = fs.root_path(tmp_root)?

  fs.write(
    fp"${tmp}/hello.c",
    """#include <stdio.h>
int main(void) { puts("hello build-essential-native"); return 0; }
""",
  )?

  let hello = fp"${tmp}/hello"
  run $cc "-dynamic" f"-Wl,-dynamic-linker,${dynlinker.display()}" fp"${tmp}/hello.c" "-o" $hello ?
  let out = run.text $dynlinker $hello ?
  let trimmed = out.trim()
  ensure(trimmed == "hello build-essential-native", "build-essential-native", f"unexpected output: ${trimmed}")?
  print "build-essential-native ok: "${trimmed}
}

main()?
