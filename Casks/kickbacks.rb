# typed: false
# frozen_string_literal: true

cask "kickbacks" do
  version "0.3.1"
  sha256 "7c4dc906fdc63d662e4f7365403623378642fd80856bc2cb5edb8589f39cfba7"

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
