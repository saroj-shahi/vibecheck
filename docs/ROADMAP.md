# VibeCheck roadmap

What's planned for VibeCheck, highest priority first. **P1** soon · **P2** nice to have · **P3** someday ·
**Tech debt** ongoing upkeep. Ideas and bug reports are welcome as
[issues](https://github.com/saroj-shahi/vibecheck/issues). How the app is built and why:
[DEVELOPMENT.md](DEVELOPMENT.md).

## Backlog

| # | Item | Priority | Notes |
|---|---|---|---|
| 1 | Translations | P2 | None yet |
| 2 | Private-API recheck after each macOS update: `IOHIDEventSystemClient*`, `responsibility_get_pid_responsible_for_pid`, SMC `PSTR`/`PDTR`/`F0Ac`, `IOBluetoothPreference{Get,Set}ControllerPowerState`, `DisplayServices{Get,Set}Brightness`, `libIOReport` (`IOReportCopyChannelsInGroup`, `IOReportCreateSubscription`, `IOReportCreateSamples`, `IOReportCreateSamplesDelta`, `IOReportChannelGetChannelName`, `IOReportChannelGetUnitLabel`, `IOReportSimpleGetIntegerValue`), IORegistry `cluster-type` / `logical-cpu-id` under `IODeviceTree:/cpus` | Tech debt | Last checked 2026-11-23 on macOS 27.2.1 (26B131), M5: all working (`--dump` + a `dlsym` probe); IOReport CPU / ANE energy read 0 for non-root (hidden), GPU works |
| 3 | Website / landing page from the brand assets | P3 | Not started |

## Not planned

- Window management, Dock tweaks, file tools, screenshots and screen recording, an uninstaller, lyrics, a
  "Dynamic Island" bar, and API cost estimates.
- Anything that needs input monitoring: a mouse jiggler, scroll direction per device, typing stats, key
  remapping.
- Fan control, a disk cleaner, a calendar in the Clock panel, keep awake with the lid closed, a sandboxed
  App Store edition, iCloud settings sync, and a dark mode toggle.
