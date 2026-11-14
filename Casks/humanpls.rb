cask "humanpls" do
  version "0.1.1"
  sha256 "1a3c0d52a81aa0e3b215da814a5b0015b81560cd38b3ff90bfd4fa7528afb0f9"

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
