#!/usr/local/bin/xsh
# Update CA certificate bundle from curl.se (Mozilla-derived).
error UpdateCertdataError = Failed(message: Str)

proc main(dest: Path = /etc/ssl/certs/ca-certificates.crt) [fs, net, error] {
  let tmp = fp"${dest.parent}/.${dest.name}.tmp"
  fs.mkdir(dest.parent)?
  fs.remove(tmp, missing_ok: true)?
  defer tmp.remove(missing_ok: true)?

  let _ = net.download(
    {url: "https://curl.se/ca/cacert.pem", dest: tmp, atomic: true, overwrite: true, fail_status: true},
  )?

  let body = tmp.read_text()?

  if ! ("-----BEGIN CERTIFICATE-----" in body) {
    return Err(UpdateCertdataError.Failed("downloaded CA bundle does not contain a PEM certificate"))
  }

  fs.rename(tmp, dest, overwrite: true)?
  print f"update-certdata: updated ${dest.display()}"
}

main(@args)?
