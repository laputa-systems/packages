error ProofError = Failed(kind: Str, message: Str)

proc ensure(condition: Bool, kind: Str, message: Str) [error] {
  if ! condition {
    return Err(ProofError.Failed(kind, message))
  }
}

proc verify_package_metadata(rootfs: Path) [fs, error] {
  let metadata_path = fp"${rootfs}/var/lib/xsh-pm/packages/ca-certificates/metadata.json"
  ensure(fs.exists(metadata_path)?, "ca-certificates-metadata", "missing package metadata")?
  let metadata: Record = json.read(metadata_path)?
  let deps: List[Str] = metadata.get("deps")?
  ensure(deps.len() == 0, "ca-certificates-deps", f"expected no runtime deps, got ${deps.join(" ")}")?
}

proc main(rootfs: Path = /rootfs) [fs, error] {
  let bundle = fp"${rootfs}/etc/ssl/certs/ca-certificates.crt"
  let helper = fp"${rootfs}/usr/bin/update-certdata"
  ensure(fs.exists(bundle)?, "ca-certificates-bundle", "missing /etc/ssl/certs/ca-certificates.crt")?
  ensure(fs.executable(helper)?, "ca-certificates-helper", "missing executable /usr/bin/update-certdata")?
  let body = bundle.read_text()?
  let cert_count = body.split("-----BEGIN CERTIFICATE-----").len() - 1
  ensure(cert_count > 0, "ca-certificates-bundle", "bundle does not contain a PEM certificate")?

  ensure(
    "https://curl.se/ca/cacert.pem" in helper.read_text()?,
    "ca-certificates-helper",
    "helper lost curl.se source policy",
  )?

  verify_package_metadata(rootfs)?
  print f"ca-certificates ok: ${cert_count} PEM certificates"
}

main(@args)?
