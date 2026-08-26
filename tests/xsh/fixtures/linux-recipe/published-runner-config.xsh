##! Minimal typed Linux config-input smoke script, run with the pinned published aarch64 runner.
use repo.linux.linux_config

proc main() [fs, env, error] {
  let fragments = linux_config.resolve_config_fragments([p"files/config/aarch64/base-aarch64.fragment"])?
  print f"linux-config-fragment ${fragments[0].display()}"
}

main()?
