# The version and sha256 lines are rewritten by .github/workflows/release.yml.
cask "snapdeck" do
  version "1.0.0"
  sha256 "f10d964cb24837191ff7ce2f673a169d0c5b4a714637fa85210e8c49819f10da"

  url "https://github.com/DeBlo12/Snapdeck/releases/download/v#{version}/Snapdeck-#{version}.zip"
  name "Snapdeck"
  desc "Window manager with Windows-style snapping, layouts and saved setups"
  homepage "https://github.com/DeBlo12/Snapdeck"

  depends_on macos: :ventura

  app "Snapdeck.app"

  zap trash: [
    "~/Library/Application Support/Snapdeck",
    "~/Library/Preferences/dev.snapdeck.Snapdeck.plist",
  ]
end
