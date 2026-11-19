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

1. Bump `CFBundleShortVersionString` in `Resources/Info.plist`, run `scripts/release.sh --zip`, then run the
   `git tag` and `gh release create` lines it prints.
2. In the tap, set `version` and `sha256` in `Casks/vibecheck.rb` to the two lines the script printed
   (the sha256 is also in `build/release/VibeCheck.zip.sha256`), commit and push.
3. Keep this copy in sync so the next tap is easy to recreate.

The cask removes the quarantine flag after install (`postflight_steps`, Homebrew 7 install-step DSL), because the app isn't notarized.
`brew uninstall --cask vibecheck` quits and removes the app and keeps settings; `--zap` also deletes them.

Homebrew 7 only loads casks from taps outside its own repos after `brew trust`, so the install instructions
start with that line. `brew audit --strict` reports that the token clashes with homebrew/core's unrelated
`vibecheck` formula; that only matters for the official cask repo, not a tap.
