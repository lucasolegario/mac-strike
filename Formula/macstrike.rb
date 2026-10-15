class Macstrike < Formula
  desc "Run Windows games on macOS — Wine bottle manager with D3D->Metal translation"
  homepage "https://github.com/lucasolegario/mac-strike"
  license "MIT"
  head "https://github.com/lucasolegario/mac-strike.git", branch: "main"

  # After your first tagged release (`gh release create v0.1.0`), fill these in so
  # `brew install macstrike` works without --HEAD:
  #   url "https://github.com/lucasolegario/mac-strike/archive/refs/tags/v0.1.0.tar.gz"
  #   sha256 "<run: brew fetch --build-from-source macstrike  to get it>"
  #   version "0.1.0"

  depends_on macos: :ventura
  depends_on arch: :arm64

  def install
    # No external dependencies, so the build needs no network.
    system "swift", "build", "-c", "release", "--disable-sandbox", "--product", "macstrike"
    bin.install ".build/release/macstrike"
  end

  def caveats
    <<~EOS
      macstrike needs an open-source Wine to run games. First-time setup:
        1. Install Wine  (see the "Quick start" in the project README)
        2. macstrike fetch-dxmt
        3. macstrike create MyGame --backend d3dmetal
      Full guide: https://github.com/lucasolegario/mac-strike
    EOS
  end

  test do
    assert_match "run Windows games", shell_output("#{bin}/macstrike 2>&1")
  end
end
