# The `net` facility provider: a one-shot that brings up the configured
# interfaces (DHCP or static) via ifup. Services that declare `need: ["net"]`
# gate on this reaching its settled state, i.e. networking is configured.
export let service = {
  name: "net",
  kind: "oneshot",
  command: process.command_argv(/usr/bin/ifup, ["ifup", "-a"], env: {PATH: "/usr/local/bin:/usr/bin:/bin"}),
  targets: [
    "boot",
  ],
  logging: "append",
}
