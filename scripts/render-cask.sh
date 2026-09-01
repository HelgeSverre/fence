#!/usr/bin/env bash
# Render Casks/fence.rb for the homebrew tap from release SHA256s.
# Usage: render-cask.sh <version> <sha_arm64_dmg> <sha_x64_dmg>
set -euo pipefail

version="$1"
arm64="$2"
x64="$3"

cat <<RUBY
cask "fence" do
  version "${version}"
  sha256 arm:   "${arm64}",
         intel: "${x64}"

  on_arm do
    url "https://github.com/HelgeSverre/fence/releases/download/v#{version}/Fence-#{version}-arm64.dmg"
  end
  on_intel do
    url "https://github.com/HelgeSverre/fence/releases/download/v#{version}/Fence-#{version}.dmg"
  end

  name "Fence"
  desc "Desktop Markdown editor with live preview, built with Elm and Electron"
  homepage "https://github.com/HelgeSverre/fence"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :big_sur

  app "Fence.app"

  zap trash: [
    "~/Library/Application Support/Fence",
    "~/Library/Preferences/no.helgesverre.fence.plist",
  ]
end
RUBY
