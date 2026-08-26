##! Published-runner regression for staged Linux Kbuild discovery workers.
use repo.linux.PKGBUILD-shared as linux_shared

proc main() [fs, process, env, time, error] {
  let root = p"/tmp/linux-kbuild-pool"
  let recipe = p"/tmp/linux-kbuild-pool/recipe"
  let source = p"/tmp/linux-kbuild-pool/source"
  let _ = fs.copy_tree(p"/src/repo/linux", recipe, parents: true, overwrite: true)?
  fs.mkdir(source)?
  fs.write(fp"${source}/.config", "")?
  fs.write(fp"${source}/Kbuild", "obj-y += one.o\n")?

  env {
    XSH_PM_SOURCE_DIR = source.display()
    XSH_PM_RECIPE_DIR = recipe.display()
    XSH_LINUX_KBUILD_DISCOVER_JOBS = "1"
  } {
    cd source {
      let plan = linux_shared.discover_package_plan("arm64")?
      if p"one.o" not in plan.objects {
        return error.fail("published staged Kbuild worker did not return the Kconfig object")
      }
    } ?
  } ?

  print "linux-kbuild-pool-published-ok"
}

main()?
