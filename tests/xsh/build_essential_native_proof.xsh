##! Behavior coverage for the build-essential-native typed-root proof contract.
pure runtime_packages() -> List[Str] {
  [
    "llvm-toolchain",
    "musl",
    "pkgconf",
    "samurai",
    "cmake",
    "m4",
    "flex",
    "bison",
    "linux",
    "muon",
  ]
}

proc runner() [process, env, error] -> Result[Path] {
  let configured = (env.get("XSH_HOST") ?? "").trim()

  return fp"${configured}" when configured != ""

  process.which("xsh")?
}

proc proof_root(ctx: TestContext) [fs, error] -> Result[Path] {
  let root = test.temp_dir(ctx, name: "build-essential-native-proof")?
  fs.mkdir(fp"${root}/usr/bin")?
  fs.mkdir(fp"${root}/boot")?

  for tool in [
    "cc",
    "c++",
    "pkg-config",
    "samu",
    "cmake",
    "m4",
    "flex",
    "bison",
    "muon",
  ] {
    fs.write(
      fp"${root}/usr/bin/${tool}",
      """typed proof fixture
""",
    )?
  }

  fs.write(
    fp"${root}/boot/vmlinuz",
    """typed proof kernel fixture
""",
  )?
  fs.mkdir(fp"${root}/var/lib/laputa")?
  write_root_receipt(root, runtime_packages())?
  root
}

proc write_root_receipt(root: Path, packages: List[Str]) [fs, error] {
  json.write(
    fp"${root}/var/lib/laputa/root.json",
    {
      format: "laputa-root-1",
      target: "aarch64-linux-musl",
      artifacts: [
        {
          package_name: package,
          package_id: f"${package}-1-1",
          artifact_key: f"artifact-${package}",
          payload: true,
        }
        for package in packages
      ],
      entries: [],
      root_sha256: "typed-root-receipt",
    },
  )?
}

proc run_build_essential_proof(xsh: Path, root: Path, stderr: Path) [process, error] -> Result[Status] {
  process.run(
    process.command_argv(
      xsh,
      [xsh.display(), "repo/build-essential-native/proof.xsh", "--", root.display()],
      stderr:,
    ),
  )
}

test test_build_essential_native_proof_uses_typed_root_receipt_without_legacy_db [fs, process, env, error] { |ctx|
  let root = proof_root(ctx)?
  let stderr = fp"${root}/proof.stderr"
  let xsh = runner()?
  fs.exists(fp"${root}/var/lib/xsh-pm/packages")? == false
  test.ok(run_build_essential_proof(xsh, root, stderr)?.ok)?

  write_root_receipt(root, [package for package in runtime_packages() if package != "linux"])?
  let missing = run_build_essential_proof(xsh, root, stderr)?
  missing.ok == false
  "missing linux artifact in typed root receipt" in stderr.read_text()?
}
