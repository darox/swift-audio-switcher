class SwiftAudioSwitcher < Formula
  desc "Switch the default macOS audio output device from the command line"
  homepage "https://github.com/darox/swift-audio-switcher"
  url "https://github.com/darox/swift-audio-switcher/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "c2062c0d10cb5c93bc617f4d06a145de256f49e6c6e0f68a4f9c0a40b71c6f5c"
  license "MIT"
  head "https://github.com/darox/swift-audio-switcher.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/swift-audio-switcher"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/swift-audio-switcher --help 2>&1")
  end
end
