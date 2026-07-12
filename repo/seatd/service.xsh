pure restart_policy() -> Record {
  return {mode: "always", delay_ms: 1000, max_delay_ms: 30000, stable_after_ms: 10000}
}

export let service = {
  name: "seatd",
  kind: "longrun",
  command: process.command_argv(
    /usr/bin/seatd,
    [
      "seatd",
      "-g",
      "seat",
      "-l",
      "info",
    ],
    env: {
      PATH: "/usr/local/bin:/usr/bin:/bin",
    },
  ),
  targets: [
    "boot",
  ],
  restart: restart_policy(),
  logging: "append",
}
