# typed: false
# frozen_string_literal: true

cask "kickbacks" do
  version "0.3.0"
  sha256 "e76eef57b5733ef4de8f2967d1be82d95e8d570a1ec71593791656742d5dd52e"

  url "https://github.com/amitray007/kickbacks/releases/download/v#{version}/Kickbacks.dmg"
  name "Kickbacks"
  desc "Read-only menu-bar app for your own Kickbacks.ai earnings (unofficial)"
  homepage "https://github.com/amitray007/kickbacks"

  depends_on macos: :ventura

  app "Kickbacks.app"

  caveats <<~EOS
    Not affiliated with Kickbacks.ai / ShiftKeys, Inc.

    Kickbacks.app is unsigned — on first launch, right-click the app → Open to bypass Gatekeeper.

    For CLI access and in-app auto-update support:
      brew install amitray007/kickbacks/kickbacks
  EOS
end
