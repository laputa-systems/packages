##! Minimal Linux Kbuild module smoke script, also run with the pinned published aarch64 runner.
use repo.linux.PKGBUILD-shared as linux_shared

proc main() [env, error] {
  let jobs = linux_shared.build_jobs()?
  print f"linux-kbuild-shared-jobs ${jobs}"
}

main()?
