##! Certificate package proof checks the runtime dependency metadata boundary.

proc runner() [env, process, error] -> Result[Path] {
  let configured = env.get("XSH_HOST") ?? ""
  if configured != "" { return fp"${configured}" }
  process.which("xsh")?
}

test ca_certificate_proof_preserves_empty_dependencies_and_rejects_invalid_metadata [fs, process, env, error] { |ctx|
  let root = test.temp_dir(ctx, name: "certificate proof")?
  let bundle = fp"${root}/etc/ssl/certs/ca-certificates.crt"
  let helper = fp"${root}/usr/bin/update-certdata"
  let metadata = fp"${root}/var/lib/xsh-pm/packages/ca-certificates/metadata.json"
  let stderr = fp"${root}/proof.stderr"
  for file in [bundle, helper, metadata] { file.parent.mkdir()? }
  bundle.write("-----BEGIN CERTIFICATE-----\nfixture\n-----END CERTIFICATE-----\n")?
  helper.write("https://curl.se/ca/cacert.pem")?
  helper.chmod(0o755)?
  let xsh = runner()?
  let command = process.command_argv(xsh, [xsh, p"repo/ca-certificates/proof.xsh", "--", root], stderr: stderr)
  json.write(metadata, {deps: [], extension: {source: "fixture"}})?
  process.run(command)?.ok
  json.write(metadata, {deps: ["unexpected-runtime"]})?
  ! process.run(command)?.ok
  "expected no runtime deps" in stderr.read_text()?
  json.write(metadata, {deps: "invalid"})?
  ! process.run(command)?.ok
  "schema" in stderr.read_text()?
  json.write(metadata, {})?
  ! process.run(command)?.ok
  "missing" in stderr.read_text()?
}
