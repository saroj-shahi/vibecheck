# Contributing

Thanks for helping! Bug reports, ideas and pull requests are welcome. Please follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Build and test
Requires macOS 14+ and Xcode (for the Swift 6 toolchain, `actool` and the App Intents tools).

```bash
./build.sh            # builds build/VibeCheck.app
swift test            # all tests must pass
.build/debug/VibeCheck --dump   # one reading from every monitor
```

`build.sh` signs with your own "Apple Development" identity if you have one, and otherwise ad hoc. The desktop
widget needs a team-signed build that matches the app group in `Resources/*.entitlements`, so it may not load in
your local build. That's expected.

## Pull requests
- Keep each PR to one change, and add tests for any logic you touch.
- Use conventional commit messages (`feat:`, `fix:`, `docs:`…).
- Follow the voice in [`branding/BRAND.md`](branding/BRAND.md) for any text people see.
- [`docs/CODEMAP.md`](docs/CODEMAP.md) says which file does what.
  [`docs/ROADMAP.md`](docs/ROADMAP.md) lists what's planned, and [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) has the design
  rules and decisions.

## Sign-off (DCO)
Every commit needs a `Signed-off-by` line, added with `git commit -s`. It certifies the
[Developer Certificate of Origin](https://developercertificate.org): you wrote the change, or have the right to
submit it, under this project's license (GPL-3.0-or-later).

## Forks
You may fork and redistribute under the GPL. Please rename your build. See [TRADEMARKS.md](TRADEMARKS.md).
