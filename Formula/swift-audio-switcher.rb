class SwiftAudioSwitcher < Formula
  desc "Switch the default macOS audio output device from the command line"
  homepage "https://github.com/darox/swift-audio-switcher"
  url "https://github.com/darox/swift-audio-switcher/archive/refs/tags/v1.0.2.tar.gz"
  sha256 "292ee3cd9e4bd86e370b2370c5240b773dc5994611d908fddc54b76c605de68f"
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
