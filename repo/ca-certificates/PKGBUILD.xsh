export let name: Str = "ca-certificates"

export let ver: Str = "2026.03.19"

export let rel: Str = "3"

export let deps: List[Str] = []

export let mkdeps: List[Str] = []

export let sources: List[Path] = [p"files/cacert.pem", p"files/update-certdata.xsh"]

export let checksums: List[Str] = [
  "b6e66569cc3d438dd5abe514d0df50005d570bfc96c14dca8f768d020cb96171",
  "bdcf5134df098da4bc5102c503c3ba6c2c75489d2b3a6d240936088438c8af92",
]

export proc build(dest: Path) [fs, error] {
  fs.install(p"cacert.pem", fp"${dest}/etc/ssl/certs/ca-certificates.crt", 0o644, parents: true, overwrite: true)?
  fs.install(p"update-certdata.xsh", fp"${dest}/usr/bin/update-certdata", 0o755, parents: true, overwrite: true)?
}
