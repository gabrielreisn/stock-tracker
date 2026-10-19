#!/bin/zsh
# Builds StockBar.app into ./build. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

# Use the Command Line Tools toolchain when Xcode's license hasn't been accepted.
if ! xcrun swift --version &>/dev/null; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/StockBar"

APP=build/StockBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/StockBar"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>StockBar</string>
  <key>CFBundleDisplayName</key><string>StockBar</string>
  <key>CFBundleIdentifier</key><string>com.gabrielreis.stockbar</string>
  <key>CFBundleExecutable</key><string>StockBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  pkill -x StockBar || true
  rm -rf ~/Applications/StockBar.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/StockBar.app
  echo "Installed to ~/Applications/StockBar.app"
fi
