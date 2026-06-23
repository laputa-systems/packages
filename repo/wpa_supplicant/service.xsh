# The wpa_supplicant facility provider: a supervised longrun that manages
# Wi-Fi association.  Services that need Wi-Fi can declare `need: ["wpa_supplicant"]`.
# By default it manages all nl80211 wireless interfaces; override by setting
# WPA_SUPPLICANT_ARGS in /etc/conf.d/wpa_supplicant.
export let service = {
  name: "wpa_supplicant",
  kind: "longrun",
  command: process.command_argv(
    /usr/sbin/wpa_supplicant,
    [
      "/usr/sbin/wpa_supplicant",
      "-B",
      "-c",
      "/etc/wpa_supplicant/wpa_supplicant.conf",
    ],
    env: {PATH: "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"},
  ),
  targets: ["boot"],
  logging: "append",
}
