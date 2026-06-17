# typed: false
# frozen_string_literal: true

class Kickbacks < Formula
  desc "Read-only CLI + menu-bar app for your own Kickbacks.ai earnings (unofficial)"
  homepage "https://github.com/amitray007/kickbacks"
  url "https://github.com/amitray007/kickbacks/releases/download/v0.3.0/kickbacks-cli-macos.zip"
  sha256 "cb16d93dfb458ba52bb2a2385d32fefa474e4be25b79496411c1efbdc109c2de"
  license "Apache-2.0"

  # Stable installs prebuilt (unsigned) arm64 binaries from the GitHub release — no toolchain
  # needed, and it works on pre-release macOS where source builds are flaky. Build from source
  # on any arch with `--HEAD`.
  depends_on arch: :arm64
  depends_on :macos

  head do
    url "https://github.com/amitray007/kickbacks.git", branch: "main"
    depends_on "bun" => :build
    depends_on xcode: :build
  end

  def install
    if build.head?
      cd "cli" do
        system "bun", "install", "--frozen-lockfile"
        system "bun", "build", "./src/cli.ts", "--compile", "--outfile", "kickbacks"
        bin.install "kickbacks"
      end
      cd "app" do
        system "swift", "build", "-c", "release", "--disable-sandbox"
        bin.install ".build/release/KickbacksBar" => "kickbacks-bar"
      end
    else
      # Prebuilt binaries, zipped flat (kickbacks + kickbacks-bar) by the release workflow.
      bin.install "kickbacks"
      bin.install "kickbacks-bar"
    end
  end

  def caveats
    <<~EOS
      Read-only companion for Kickbacks.ai — not affiliated with Kickbacks.ai / ShiftKeys, Inc.

      Stable installs prebuilt, unsigned binaries from the GitHub release. To build from source
      instead: brew install --HEAD amitray007/kickbacks/kickbacks

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
