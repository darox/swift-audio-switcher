class SwiftAudioSwitcher < Formula
  desc "Switch the default macOS audio output device from the command line"
  homepage "https://github.com/darox/swift-audio-switcher"
  url "https://github.com/darox/swift-audio-switcher/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "9ac080c6bb82142d129d42e27d0d8b1daf0d0c029f7c4cc57d345bf4ff1ade87"
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
