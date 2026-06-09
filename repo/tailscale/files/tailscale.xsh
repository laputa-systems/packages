pure restart_policy() -> Record {
  return {mode: "always", delay_ms: 1000, max_delay_ms: 30000, stable_after_ms: 10000}
}

pure tailscaled_argv(state: Path, socket: Path, userspace_networking: Bool) -> List[Str] {
  let argv = [
    "tailscaled",
    "--state",
    state.display(),
    "--socket",
    socket.display(),
    "--encrypt-state=false",
    "--hardware-attestation=false",
  ]

  if userspace_networking {
    return argv.push("--tun=userspace-networking")
  }

  return argv
}

pure tailscale_service(state: Path, socket: Path, userspace_networking: Bool) -> Record {
  return {
    name: "tailscaled",
    command: process.command_argv(
      /usr/bin/tailscaled,
      tailscaled_argv(state, socket, userspace_networking),
      env: {PATH: "/usr/local/bin:/usr/bin:/bin"},
    ),
    restart: restart_policy(),
  }
}

export let services: List[Record] = [
  tailscale_service(/var/lib/tailscale/tailscaled.state, /run/tailscale/tailscaled.sock, false),
]

export proc service_records() [env, error] -> Result[List[Record]] {
  let state = env.path("XINIT_TAILSCALE_STATE", /var/lib/tailscale/tailscaled.state)?
  let socket = env.path("XINIT_TAILSCALE_SOCKET", /run/tailscale/tailscaled.sock)?
  let userspace_networking = env.bool("XINIT_TAILSCALE_USERSPACE_NETWORKING", false)?
  return [tailscale_service(state, socket, userspace_networking)]
}
