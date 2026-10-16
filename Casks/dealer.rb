# Homebrew cask for Dealer. The canonical copy lives in github.com/chantastic/homebrew-tap as
# Casks/dealer.rb; this one is the template. scripts/update-cask.sh rewrites `version` and
# `sha256` for a release, and the release workflow attaches the result to each GitHub Release.
cask "dealer" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/chantastic/dealer/releases/download/v#{version}/Dealer.dmg"
  name "Dealer"
  desc "Menu bar link router that opens URLs in the right Google Chrome profile"
  homepage "https://github.com/chantastic/dealer"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :ventura

  app "Dealer.app"
  binary "#{appdir}/Dealer.app/Contents/MacOS/deal"

  uninstall quit: "dev.chan.dealer"

  zap trash: [
    "~/.config/dealer",
    "~/Library/Caches/dev.chan.dealer",
    "~/Library/HTTPStorages/dev.chan.dealer",
    "~/Library/Preferences/dev.chan.dealer.plist",
  ]
end
