##! Regression coverage for the m4 package proof's literal input-path boundary.
proc runner() [fs, process, env, error] -> Result[Path] {
  let configured = (env.get("XSH_HOST") ?? "").trim()

  if configured != "" {
    let selected = Path(configured)

    if selected.exists()? {
      return selected
    }
  }

  process.which("xsh")?
}

proc test_m4_proof_reads_its_file_operand_and_handles_directory_rejection(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "m4-proof-file-operand")?
  let m4 = fp"${root}/usr/bin/m4"
  let stderr = fp"${root}/proof.stderr"
  let xsh = runner()?
  fs.mkdir(m4.parent)?

  # The proof invokes the staged runner as an executable.  Its shebang points
  # at this host test runner solely so the behavior can be checked without a
  # target rootfs; the package payload still ships `#!/bin/xsh`.
  let staged = fs.read_text(p"repo/m4/files/m4.xsh")?.replace("#!/bin/xsh", f"#!${xsh.display()}")
  fs.write(m4, staged)?
  fs.chmod(m4, 0o755)?

  let status = process.run(
    process.command_argv(
      xsh,
      [xsh.display(), "repo/m4/proof.xsh", "--", root.display()],
      stderr: stderr,
    ),
  )?
  if ! status.ok {
    test.fail(stderr.read_text()?)?
  }
}

proc test_bison_stack_proof_passes_the_generated_m4_file_operand(ctx: TestContext) [fs, process, env, error] {
  let root = test.temp_dir(ctx, name: "bison-stack-m4-operand")?
  let stderr = fp"${root}/proof.stderr"
  let xsh = runner()?
  fs.mkdir(fp"${root}/usr/bin")?

  let m4 = fs.read_text(p"repo/m4/files/m4.xsh")?.replace("#!/bin/xsh", f"#!${xsh.display()}")
  fs.write(fp"${root}/usr/bin/m4", m4)?
  fs.write(fp"${root}/usr/bin/flex", f"#!${xsh.display()}\nprint \"flex 2.6 fixture\"\n")?
  fs.write(fp"${root}/usr/bin/bison", f"#!${xsh.display()}\nprint \"GNU Bison fixture\"\n")?
  for tool in ["m4", "flex", "bison"] {
    fs.chmod(fp"${root}/usr/bin/${tool}", 0o755)?
  }

  let status = process.run(
    process.command_argv(
      xsh,
      [xsh.display(), "repo/bison/proof-stack.xsh", "--", root.display()],
      stderr: stderr,
    ),
  )?
  if ! status.ok {
    test.fail(stderr.read_text()?)?
  }
}
