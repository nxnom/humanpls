cask "humanpls" do
  version "0.1.0"
  sha256 "8ff1e07c32eee2bd1fac6f20621c89b5d59ca97fd43d21873b040a0b963a91fd"

  url "https://github.com/nxnom/humanpls/releases/download/v#{version}/humanpls-#{version}.dmg"
  name "humanpls"
  desc "Native macOS popup that lets an AI agent ask you to pick between options"
  homepage "https://github.com/nxnom/humanpls"

  depends_on macos: ">= :sonoma"

  app "humanpls.app"
  # puts the command on the PATH: no manual step
  binary "#{appdir}/humanpls.app/Contents/MacOS/humanpls"

  zap trash: "~/Library/Application Support/humanpls"
end
