use pm.proof

proc main(root: Path = /rootfs) [fs, process, env, error] {
  proof.package_metadata(root, "pixman")?
  proof.target_elf(root, p"usr/lib/libpixman-1.so.0", "pixman")?
  let readelf = proof.readelf_tool()?
  let dynamic = run.text $readelf "-d" fp"${root}/usr/lib/libpixman-1.so.0" ?
  proof.ensure(
    !dynamic.contains("build-work"),
    "proof-pixman",
    "libpixman contains an executor-local build path",
  )?
  print "pixman ok"
}

main(@args)?
