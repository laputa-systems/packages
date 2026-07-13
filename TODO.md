# TODO

## Publish remote package tarballs and sidecars atomically

The remote package index, binary tarball, and metadata sidecar must describe
the same package artifact. Publication should stage the tarball and sidecar,
verify that the sidecar's complete `files` records match the tarball, and then
publish a consistent version together with the index update. Readers should
never observe a new index entry with an older or mismatched sidecar.

Until this is implemented, PM validates cached sidecars against the verified
tarball and falls back to metadata embedded in the tarball when the generic
file records differ.
