# Privacy

VibeCheck runs on your Mac. It has no account, no analytics, no crash reporting and no server of its own.

## What it reads, locally
- System stats from macOS: CPU, memory, disk, network, sensors, battery and processes.
- AI agent usage from the local log files that Claude Code, Codex, GitHub Copilot and opencode write in your
  home folder. These are counted on your Mac and never sent anywhere.
- Your Wi-Fi network name, only if you turn on the Wi-Fi keep-awake trigger. Your location is never used or
  stored.

## Network requests
| When | To | What is sent |
|---|---|---|
| Update check (at most once a day; can be turned off in Settings → About) | `api.github.com` | Nothing personal; a standard HTTPS request for the latest release |
| Weather (only if the Weather module is on) | `api.open-meteo.com`, `geocoding-api.open-meteo.com` | The city you picked, or its coordinates |
| Public IP (only if you turn it on) | `api.ipify.org` | A standard HTTPS request |
| Claude live limits (only if you turn it on) | Your own Claude Code asks Anthropic, the same way `/usage` does | VibeCheck never reads your credentials or Keychain |

Settings stay in the `local.vibecheck.app` defaults domain on your Mac. Uninstalling the app and running
`defaults delete local.vibecheck.app` removes them.
