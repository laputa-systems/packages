use pm.recipe

proc main(pkg_dir: Path, src: Path, dest: Path) [fs, process, env, error] {
  let pkg = recipe.load_package(pkg_dir)?
  recipe.call_prepare(pkg, src)?
  fs.remove(dest, missing_ok: true)?
  fs.mkdir(dest)?
  recipe.call_build(pkg, src, dest)?
}

main(@args)?
