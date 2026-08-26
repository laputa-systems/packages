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

  if configured != "" {
    return fp"${configured}"
  }

  process.which("xsh")?
}

proc proof_root(ctx: TestContext) [fs, error] -> Result[Path] {
  let root = test.temp_dir(ctx, name: "build-essential-native-proof")?
  fs.mkdir(fp"${root}/usr/bin")?
  fs.mkdir(fp"${root}/boot")?

  for tool in ["cc", "c++", "pkg-config", "samu", "cmake", "m4", "flex", "bison", "muon"] {
    fs.write(fp"${root}/usr/bin/${tool}", "typed proof fixture\n")?
  }

  fs.write(fp"${root}/boot/vmlinuz", "typed proof kernel fixture\n")?
  fs.mkdir(fp"${root}/var/lib/laputa")?
  json.write(
    fp"${root}/var/lib/laputa/root.json",
    {
      format: "laputa-root-1",
      target: "aarch64-linux-musl",
      artifacts: [
        {package_name: package, package_id: f"${package}-1-1", artifact_key: f"artifact-${package}", payload: true}
        for package in runtime_packages()
      ],
      entries: [],
      root_sha256: "typed-root-receipt",
    },
  )?
  root
}

proc run_build_essential_proof(xsh: Path, root: Path, stderr: Path) [process, error] -> Result[Status] {
  process.run(
    process.command_argv(
      xsh,
      [xsh.display(), "repo/build-essential-native/proof.xsh", "--", root.display()],
      stderr: stderr,
    ),
  )
}

proc test_build_essential_native_proof_uses_typed_root_receipt_without_legacy_db(ctx: TestContext) [fs, process, env, error] {
  let root = proof_root(ctx)?
  let stderr = fp"${root}/proof.stderr"
  let xsh = runner()?
  test.eq(fs.exists(fp"${root}/var/lib/xsh-pm/packages")?, false)?
  test.ok(run_build_essential_proof(xsh, root, stderr)?.ok)?

  let receipt: Record = json.read(fp"${root}/var/lib/laputa/root.json")?
  let artifacts: List[Record] = receipt.get("artifacts")?
  let without_linux = [artifact for artifact in artifacts if artifact.get("package_name")? != "linux"]
  json.write(fp"${root}/var/lib/laputa/root.json", {...receipt, artifacts: without_linux})?
  let missing = run_build_essential_proof(xsh, root, stderr)?
  test.eq(missing.ok, false)?
  test.contains(stderr.read_text()?, "missing linux artifact in typed root receipt")?
}
