pure restart_policy() -> Record {
  return {mode: "always", delay_ms: 1000, max_delay_ms: 30000, stable_after_ms: 10000}
}

export let services: List[Record] = [
  {
    name: "mdevd",
    command: process.command_argv(
      /usr/bin/mdevd,
      ["mdevd", "-O", "4", "-f", "/etc/mdev.conf", "-C"],
      env: {PATH: "/usr/local/bin:/usr/bin:/bin"},
    ),
    restart: restart_policy(),
    log: {mode: "append"},
  },
]
