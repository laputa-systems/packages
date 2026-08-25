use PKGBUILD

proc main(src: Path, dest: Path) [fs, process, env, error] {
  fs.remove(dest, missing_ok: true)?
  fs.mkdir(dest)?

  cd $src {
    PKGBUILD.build(dest)?
  } ?
}

main(@args)?
