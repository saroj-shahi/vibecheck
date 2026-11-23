# Homebrew tap

`vibecheck.rb` is the cask for the `saroj-shahi/homebrew-tap` repo. It installs the `VibeCheck.zip` asset of a
GitHub release made by `scripts/release.sh --zip`. People install with:

```bash
brew tap saroj-shahi/tap
brew trust --cask saroj-shahi/tap/vibecheck   # Homebrew asks you to trust taps from outside its own repos
brew install --cask saroj-shahi/tap/vibecheck
```

## Create the tap (once)

1. Create a public GitHub repo named exactly `homebrew-tap` under `saroj-shahi`.
2. Copy this file into it as `Casks/vibecheck.rb`, with the real `sha256` (see below), and push.
3. Check it: `brew trust --cask saroj-shahi/tap/vibecheck && brew tap saroj-shahi/tap && brew audit --cask --strict saroj-shahi/tap/vibecheck && brew install --cask saroj-shahi/tap/vibecheck`.

## Each release

Bump `CFBundleShortVersionString` in `Resources/Info.plist`, commit and push to `main`, then run
`scripts/release.sh --publish`. After the GitHub release it writes this file into the tap as `Casks/vibecheck.rb`
with the new `version` and `sha256`, and pushes. So edit the cask here, never in the tap; a change here reaches
the tap with the next release.

The cask removes the quarantine flag after install (`postflight_steps`, Homebrew 7 install-step DSL), because the app isn't notarized.
`brew uninstall --cask saroj-shahi/tap/vibecheck` quits and removes the app and keeps settings; `--zap` also deletes them.

Homebrew 7 only loads casks from taps outside its own repos after `brew trust`, so the install instructions
start with that line. `brew audit --strict` reports that the token clashes with homebrew/core's unrelated
`vibecheck` formula; that only matters for the official cask repo, not a tap.
