# Privacy

VibeCheck runs on your Mac. It has no account, no analytics, no crash reporting and no server of its own.

## What it reads, locally
- System stats from macOS: CPU, memory, disk, network, sensors, battery and processes.
- AI agent usage from the local log files that Claude Code, Codex, GitHub Copilot and opencode write in your
  home folder. These are counted on your Mac and never sent anywhere.
- Your Wi-Fi network name, only if you turn on the Wi-Fi keep-awake trigger. Your location is never used or
  stored.
- Your Apple Reminders, only if you turn on the To-do module: the one list you pick is shown, and reminders are
  added, completed or deleted only when you do it. Nothing is copied out of Reminders or stored by VibeCheck.
- Each app's estimated energy use (from macOS), totalled for today and yesterday in `energy.json` (readable
  only by you) and nothing older.

## Network requests
| When | To | What is sent |
|---|---|---|
| Update check (at most once a day; can be turned off in Settings → About) | `api.github.com` | Nothing personal; a standard HTTPS request for the latest release |
| Weather (only if the Weather module is on) | `api.open-meteo.com`, `geocoding-api.open-meteo.com` | The city you picked, or its coordinates |
| Public IP (only if you turn it on) | `api.ipify.org` | A standard HTTPS request |
| Claude live limits (only if you turn it on) | Your own Claude Code asks Anthropic, the same way `/usage` does | VibeCheck never reads your credentials or Keychain |

Settings stay in the `io.github.saroj-shahi.vibecheck` defaults domain on your Mac, and history in
`~/Library/Application Support/VibeCheck`. To remove everything after uninstalling, run
`defaults delete io.github.saroj-shahi.vibecheck` and delete that folder. Versions 1.5 and earlier used
`local.vibecheck.app`, so run `defaults delete local.vibecheck.app` too if you used one of them.
