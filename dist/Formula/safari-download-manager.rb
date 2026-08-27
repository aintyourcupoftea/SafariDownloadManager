class SafariDownloadManager < Formula
  desc "IDM-style download interception for Safari"
  homepage "https://github.com/aintyourcupoftea/SafariDownloadManager"
  url "https://github.com/aintyourcupoftea/SafariDownloadManager/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "b536eb0d232a7ac04d2ed63c20c6a582fbd735de7421030b4b341546cbe6e2f9"
  license "GPL-3.0-or-later"
  head "https://github.com/aintyourcupoftea/SafariDownloadManager.git", branch: "main"

  depends_on "aria2"
  # Verified on macOS 26 (Tahoe). Local-mode interception and the QUIC
  # workaround have not been validated on older majors.
  depends_on macos: :sonoma

  def install
    libexec.install Dir["dist/libexec/*"]
    bin.install "dist/bin/sdm"

    # No compiler is used on purpose. Building the SwiftUI front-end here made
    # Homebrew enforce its Xcode floor ("Your Xcode is too outdated"), which
    # blocks installation for anyone whose Xcode does not match Homebrew's
    # expectation - a hard failure for a tool that is otherwise pure scripts.
    # The GUI ships separately; the CLI is fully functional without it.
  end

  def caveats
    <<~EOS
      First-time setup (no sudo required):

        sdm setup

      mitmproxy is distributed as a Homebrew *cask*, and a formula cannot depend
      on a cask, so `sdm setup` installs it for you if it is missing. The cask is
      required rather than optional: it carries the signed macOS network
      redirector that interception is built on.

      That generates the interception CA and trusts it in your LOGIN keychain
      only, writes launch agents, and starts the services.

      Then approve mitmproxy's network extension once:

        System Settings -> General -> Login Items & Extensions -> Network Extensions
        enable "network-extension" (org.mitmproxy.macos-redirector)

      Turn it on:

        sdm on
        sdm status

      To remove everything, including untrusting the CA:

        sdm uninstall
    EOS
  end

  test do
    assert_match "IDM-style download interception", shell_output("#{bin}/sdm 2>&1")
  end
end
