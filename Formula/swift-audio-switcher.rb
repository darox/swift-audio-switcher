class SwiftAudioSwitcher < Formula
  desc "Switch the default macOS audio output device from the command line"
  homepage "https://github.com/darox/swift-audio-switcher"
  url "https://github.com/darox/swift-audio-switcher/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "40f7623171845077fce10364ddcb465d431f160299438d6c8a67d5474f85d48a"
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
