##! XSH module `proof` package and build operations.
use pm.proof

proc main(root: Path = /rootfs) [fs, process, env, error] {
  proof.package_metadata(root, "libpng")?
  proof.target_elf(root, p"usr/lib/libpng16.so.16", "libpng")?

  # A shared libpng must not defer optional ARM NEON implementations to a
  # nonexistent DSO.  The historical broken artifact passed metadata checks
  # but failed only when foot loaded it in the guest.
  let readelf = proof.readelf_tool()?
  let symbols = run.text $readelf "-Ws" fp"${root}/usr/lib/libpng16.so.16" ?

  for symbol in [
    "png_riffle_palette_neon",
    "png_do_expand_palette_rgba8_neon",
    "png_do_expand_palette_rgb8_neon",
    "png_init_filter_functions_neon",
  ] {
    proof.ensure(
      !symbols.contains(f"UND ${symbol}"),
      "proof-libpng",
      f"libpng has unresolved optional ARM helper ${symbol}",
    )?
  }

  print "libpng ok"
}

main(@args)?
