cask "hrefto" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256"

  url "https://github.com/broady/hrefto/releases/download/v#{version}/HrefTo.app.zip"
  name "HrefTo"
  desc "macOS URL router and browser picker"
  homepage "https://github.com/broady/hrefto"

  depends_on macos: ">= :sonoma"

  app "HrefTo.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/HrefTo.app"]
  end

  zap trash: "~/Library/Application Support/HrefTo"
end
