pure restart_policy() -> Record {
  return {mode: "always", delay_ms: 1000, max_delay_ms: 30000, stable_after_ms: 10000}
}

pure dropbear_argv(bind: Str, port: Int, host_key: Path) -> List[Str] {
  if host_key.display() != "" {
    return ["dropbear", "-F", "-E", "-p", f"${bind}:${port}", "-r", host_key.display()]
  }

  return ["dropbear", "-F", "-E", "-R", "-p", f"${bind}:${port}"]
}

pure dropbear_service(bind: Str, port: Int, host_key: Path) -> Record {
  let argv = dropbear_argv(bind, port, host_key)
  return {name: "dropbear", command: process.command_argv(/usr/bin/dropbear, argv), restart: restart_policy()}
}

export let services: List[Record] = [dropbear_service("0.0.0.0", 22, p"")]

export proc service_records() [env, error] -> Result[List[Record]] {
  let bind: Str = env.get_or("XINIT_DROPBEAR_BIND", "0.0.0.0")?
  let port = env.int("XINIT_DROPBEAR_PORT", 22)?
  let host_key: Path = env.path("XINIT_DROPBEAR_HOST_KEY", p"")?
  return [dropbear_service(bind, port, host_key)]
}
