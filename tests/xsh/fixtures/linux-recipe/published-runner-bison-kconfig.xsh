##! Published-runner regression for Linux's exact Kconfig bison invocation.
proc main() [fs, process, env, error] {
  let root = p"/tmp/linux-bison-kconfig"
  let grammar = p"/tmp/linux-bison-kconfig/scripts/kconfig/parser.y"
  let output = p"/tmp/linux-bison-kconfig/scripts/kconfig/parser.tab.c"
  let header = p"/tmp/linux-bison-kconfig/scripts/kconfig/parser.tab.h"
  let missing_log = p"/tmp/linux-bison-kconfig/missing.err"
  fs.mkdir(grammar.parent)?
  fs.write(grammar, "%token WORD\n%start input\n%%\ninput: WORD ;\n%%\n")?

  let success = process.run(
    process.command_argv(
      /xsh-release/bin/xsh,
      [
        "/xsh-release/bin/xsh",
        "/src/repo/bison/files/bison.xsh",
        "--",
        "-o",
        "scripts/kconfig/parser.tab.c",
        "--defines=scripts/kconfig/parser.tab.h",
        "-t",
        "-l",
        "scripts/kconfig/parser.y",
      ],
      cwd: root,
      env: {XSH_BISON_NO_UPSTREAM: "1"},
    ),
  )?
  if ! success.ok or ! output.exists()? or ! header.exists()? {
    return error.fail("published bison did not generate Linux Kconfig parser outputs")
  }

  let missing = process.run(
    process.command_argv(
      /xsh-release/bin/xsh,
      [
        "/xsh-release/bin/xsh",
        "/src/repo/bison/files/bison.xsh",
        "--",
        "-o",
        "scripts/kconfig/parser.tab.c",
        "--defines=scripts/kconfig/parser.tab.h",
        "-t",
        "-l",
        "scripts/kconfig/missing.y",
      ],
      cwd: root,
      env: {XSH_BISON_NO_UPSTREAM: "1"},
      stderr: missing_log,
    ),
  )?
  if missing.ok or ! missing_log.read_text()?.contains("No such file or directory") {
    return error.fail("published bison accepted a missing Linux Kconfig grammar")
  }

  print "linux-bison-kconfig-published-ok"
}

main()?
