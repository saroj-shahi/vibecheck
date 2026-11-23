cask "vibecheck" do
  version "1.5"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # from scripts/release.sh --zip

  url "https://github.com/saroj-shahi/vibecheck/releases/download/v#{version}/VibeCheck.zip"
  name "VibeCheck"
  desc "Mac health in one ring, live in the menu bar"
  homepage "https://github.com/saroj-shahi/vibecheck"

  depends_on macos: :sonoma

  app "VibeCheck.app"

  # Not notarized (no paid Developer ID): clear the quarantine flag Homebrew sets, or Gatekeeper blocks the app.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/VibeCheck.app"]
  end

  uninstall quit: [
    "io.github.saroj-shahi.vibecheck",
    "local.vibecheck.app", # 1.5 and earlier
  ]

  zap trash: [
    "~/Library/Application Support/VibeCheck",
    "~/Library/Group Containers/77HKFF78Z8.io.github.saroj-shahi.vibecheck",
    "~/Library/Preferences/io.github.saroj-shahi.vibecheck.plist",
    # 1.5 and earlier
    "~/Library/Group Containers/77HKFF78Z8.local.vibecheck",
    "~/Library/Preferences/local.vibecheck.app.plist",
  ]
end
