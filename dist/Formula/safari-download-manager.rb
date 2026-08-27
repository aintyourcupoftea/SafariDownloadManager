class SafariDownloadManager < Formula
  desc "IDM-style download interception for Safari"
  homepage "https://github.com/aintyourcupoftea/safari-download-manager"
  url "https://github.com/aintyourcupoftea/safari-download-manager/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_RELEASE_SHA256"
  license "MIT"
  head "https://github.com/aintyourcupoftea/safari-download-manager.git", branch: "main"

  depends_on "aria2"
  depends_on "mitmproxy"
  depends_on :macos
  depends_on macos: :ventura

  def install
    libexec.install Dir["dist/libexec/*"]
    bin.install "dist/bin/sdm"

    # Build the SwiftUI front-end if a toolchain is present. The CLI is fully
    # functional without it, so a missing toolchain is not fatal.
    if File.directory?("app/SafariDM/Sources") && which("swiftc")
      sdk = Utils.safe_popen_read("xcrun", "--show-sdk-path", "--sdk", "macosx").chomp
      system "xcrun", "swiftc", "-O",
             "-target", "arm64-apple-macosx14.0", "-sdk", sdk,
             "-framework", "SwiftUI", "-framework", "AppKit", "-framework", "Foundation",
             *Dir["app/SafariDM/Sources/*.swift"], "-o", "SafariDM"
        app = prefix/"Safari Download Manager.app"
        (app/"Contents/MacOS").mkpath
        (app/"Contents/Resources").mkpath
        cp "SafariDM", app/"Contents/MacOS/SafariDM"
        (app/"Contents/Info.plist").write <<~PLIST
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0"><dict>
            <key>CFBundleName</key><string>Safari Download Manager</string>
            <key>CFBundleIdentifier</key><string>com.sdm.SafariDownloadManager</string>
            <key>CFBundleExecutable</key><string>SafariDM</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>CFBundleShortVersionString</key><string>#{version}</string>
            <key>LSMinimumSystemVersion</key><string>14.0</string>
            <key>NSHighResolutionCapable</key><true/>
          </dict></plist>
        PLIST
    end
  end

  def caveats
    <<~EOS
      First-time setup (no sudo required):

        sdm setup

      That generates the interception CA and trusts it in your LOGIN keychain
      only, writes launch agents, and starts the services.

      Then approve mitmproxy's network extension once:

        System Settings -> General -> Login Items & Extensions -> Network Extensions
        enable "network-extension" (org.mitmproxy.macos-redirector)

      Turn it on:

        sdm on
        sdm status

      The GUI, if it was built:

        open #{prefix}/"Safari Download Manager.app"

      To remove everything, including untrusting the CA:

        sdm uninstall
    EOS
  end

  test do
    assert_match "safari-download-manager", shell_output("#{bin}/sdm 2>&1")
  end
end
