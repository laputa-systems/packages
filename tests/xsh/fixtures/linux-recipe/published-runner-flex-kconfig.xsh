##! Published-runner regression for Linux's exact Kconfig flex invocation.
proc main() [fs, process, env, error] {
  let root = p"/tmp/linux-flex-kconfig"
  let lexer = p"/tmp/linux-flex-kconfig/scripts/kconfig/lexer.l"
  let output = p"/tmp/linux-flex-kconfig/scripts/kconfig/lexer.lex.c"
  let missing_log = p"/tmp/linux-flex-kconfig/missing.err"
  fs.mkdir(lexer.parent)?
  fs.write(lexer, "%%\n[a-z]+ return 1;\n%%\n")?

  let success = process.run(
    process.command_argv(
      /xsh-release/bin/xsh,
      [
        "/xsh-release/bin/xsh",
        "/src/repo/flex/files/flex.xsh",
        "--",
        "-oscripts/kconfig/lexer.lex.c",
        "-L",
        "scripts/kconfig/lexer.l",
      ],
      cwd: root,
      env: {XSH_FLEX_NO_UPSTREAM: "1"},
    ),
  )?
  if ! success.ok or ! output.exists()? {
    return error.fail("published flex did not generate Linux Kconfig lexer output")
  }

  let missing = process.run(
    process.command_argv(
      /xsh-release/bin/xsh,
      [
        "/xsh-release/bin/xsh",
        "/src/repo/flex/files/flex.xsh",
        "--",
        "-oscripts/kconfig/lexer.lex.c",
        "-L",
        "scripts/kconfig/missing.l",
      ],
      cwd: root,
      env: {XSH_FLEX_NO_UPSTREAM: "1"},
      stderr: missing_log,
    ),
  )?
  if missing.ok or ! missing_log.read_text()?.contains("No such file or directory") {
    return error.fail("published flex accepted a missing Linux Kconfig lexer")
  }

  print "linux-flex-kconfig-published-ok"
}

main()?
