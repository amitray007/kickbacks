# typed: strict
# frozen_string_literal: true

class Kickbacks < Formula
  desc "Read-only CLI + menu-bar app for your own Kickbacks.ai earnings (unofficial)"
  homepage "https://github.com/amitray007/kickbacks"
  url "https://github.com/amitray007/kickbacks/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "4157e97482989c19ef02c4fd0599f5e0099edc3a53971e2acb944fde624a8abf"
  license "Apache-2.0"
  head "https://github.com/amitray007/kickbacks.git", branch: "main"

  depends_on "bun" => :build
  depends_on xcode: :build
  depends_on :macos

  def install
    cd "cli" do
      system "bun", "install", "--frozen-lockfile"
      system "bun", "build", "./src/cli.ts", "--compile", "--outfile", "kickbacks"
      bin.install "kickbacks"
    end
    cd "app" do
      system "swift", "build", "-c", "release", "--disable-sandbox"
      bin.install ".build/release/KickbacksBar" => "kickbacks-bar"
    end
  end

  def caveats
    <<~EOS
      Read-only companion for Kickbacks.ai — not affiliated with Kickbacks.ai / ShiftKeys, Inc.

      Get started:
        kickbacks login
        kickbacks                 # earnings dashboard
        kickbacks poller install  # background sampling + stall/cap alerts (launchd)
        kickbacks bar install     # menu-bar app at login
    EOS
  end

  test do
    assert_match "kickbacks status", shell_output("#{bin}/kickbacks status 2>&1")
    assert_path_exists bin/"kickbacks-bar"
  end
end
