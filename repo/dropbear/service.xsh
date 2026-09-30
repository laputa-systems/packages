##! XSH module `service` package and build operations.
pure restart_policy() -> Record {
  {mode: "always", delay_ms: 1000, max_delay_ms: 30000, stable_after_ms: 10000}
}

pure dropbear_argv(bind: Str, port: Int, host_key: Path) -> List[Str] {
  guard host_key.display() == "" else {
    return ["dropbear", "-F", "-E", "-p", f"${bind}:${port}", "-r", host_key.display()]
  }

  ["dropbear", "-F", "-E", "-R", "-p", f"${bind}:${port}"]
}

pure dropbear_service(bind: Str, port: Int, host_key: Path) -> Record {
  let argv = dropbear_argv(bind, port, host_key)
  {name: "dropbear", command: process.command_argv(/usr/bin/dropbear, argv), restart: restart_policy()}
}

let bind = env.get("XINIT_DROPBEAR_BIND") ?? "0.0.0.0"
let port = (env.get("XINIT_DROPBEAR_PORT") ?? "22").parse_int()?
let host_key = env.path("XINIT_DROPBEAR_HOST_KEY", p"")?
let service_record = dropbear_service(bind, port, host_key)

## Exported declaration `service`.
export let service = {
  name: service_record.name,
  kind: "longrun",
  command: service_record.command,
  targets: [
    "boot",
  ],
  dependencies: {
    need: [
      "net",
    ],
  },
  restart: service_record.restart,
  logging: "append",
}
