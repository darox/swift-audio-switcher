class SwiftAudioSwitcher < Formula
  desc "Switch the default macOS audio output device from the command line"
  homepage "https://github.com/darox/swift-audio-switcher"
  url "https://github.com/darox/swift-audio-switcher/archive/refs/tags/v1.1.2.tar.gz"
  sha256 "0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5"
  license "MIT"
  head "https://github.com/darox/swift-audio-switcher.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/swift-audio-switcher"
    bin.install ".build/release/airplay-pick"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/swift-audio-switcher --help 2>&1")
    assert_match "usage", shell_output("#{bin}/airplay-pick --help 2>&1")
  end
end
