# typed: strict
# frozen_string_literal: true

class Kickback < Formula
  desc "Read-only CLI + menu-bar app for your own Kickbacks.ai earnings (unofficial)"
  homepage "https://github.com/USER/kickbacks"
  url "https://github.com/USER/kickbacks/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "replace_on_release"
  license "Apache-2.0"
  head "https://github.com/USER/kickbacks.git", branch: "main"

  depends_on "bun" => :build
  depends_on xcode: :build
  depends_on :macos

  def install
    cd "cli" do
      system "bun", "install", "--frozen-lockfile"
      system "bun", "build", "./src/cli.ts", "--compile", "--outfile", "kickback"
      bin.install "kickback"
    end
    cd "app" do
      system "swift", "build", "-c", "release", "--disable-sandbox"
      bin.install ".build/release/KickbackBar" => "kickback-bar"
    end
  end

  def caveats
    <<~EOS
      Read-only companion for Kickbacks.ai — not affiliated with Kickbacks.ai / ShiftKeys, Inc.

      Get started:
        kickback login
        kickback                 # earnings dashboard
        kickback poller install  # background sampling + stall/cap alerts (launchd)
        kickback bar install     # menu-bar app at login
    EOS
  end

  test do
    assert_match "kickback status", shell_output("#{bin}/kickback status 2>&1")
    assert_path_exists bin/"kickback-bar"
  end
end
