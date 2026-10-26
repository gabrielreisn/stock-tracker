#!/bin/zsh
# Builds a universal StockBar.app into ./build.
#   ./build.sh            build the app
#   ./build.sh --dmg      also package build/StockBar-<version>.dmg
#   ./build.sh --install  copy it to ~/Applications and launch it
# VERSION=1.2.0 ./build.sh --dmg   sets the app version (default: latest git tag, else 0.0.0)
set -euo pipefail
cd "$(dirname "$0")"

# Use the Command Line Tools toolchain when Xcode's license hasn't been accepted.
if ! xcrun swift --version &>/dev/null; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# One build per architecture, merged into a universal binary (multi-arch in one step needs full Xcode).
for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx15.0"
done

APP=build/StockBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  .build/arm64-apple-macosx/release/StockBar \
  .build/x86_64-apple-macosx/release/StockBar \
  -output "$APP/Contents/MacOS/StockBar"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Translations: <lang>.lproj/Localizable.strings, looked up from the main bundle by SwiftUI and String(localized:).
cp -R Resources/*.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>StockBar</string>
  <key>CFBundleDisplayName</key><string>StockBar</string>
  <key>CFBundleIdentifier</key><string>com.gabrielreis.stockbar</string>
  <key>CFBundleExecutable</key><string>StockBar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>pt-BR</string></array>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.finance</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Sign with a stable identity when there is one, so macOS keeps "Always Allow" for the Keychain item across builds
# (an ad-hoc signature changes with every build). CI imports it from secrets; locally it's in the login keychain.
IDENTITY="${CODESIGN_IDENTITY:-StockBar Code Signing}"
if [[ -n "${SIGNING_P12_BASE64:-}" ]]; then
  KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
  security create-keychain -p ci "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN"
  security unlock-keychain -p ci "$KEYCHAIN"
  echo "$SIGNING_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/signing.p12"
  security import "$RUNNER_TEMP/signing.p12" -k "$KEYCHAIN" -P "$SIGNING_P12_PASSWORD" -T /usr/bin/codesign
  security set-key-partition-list -S apple-tool:,apple: -s -k ci "$KEYCHAIN" >/dev/null
  security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
fi
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "No '$IDENTITY' certificate: signing ad hoc (Keychain access will be asked again after each build)"
  codesign --force --sign - "$APP"
fi
echo "Built $APP $VERSION ($BUILD_NUMBER), $(lipo -archs "$APP/Contents/MacOS/StockBar")"

case "${1:-}" in
  --dmg)
    DMG="build/StockBar-$VERSION.dmg"
    STAGING="$(mktemp -d)"
    cp -R "$APP" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"   # drag-to-install target
    rm -f "$DMG"
    hdiutil create -volname "StockBar $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
    rm -rf "$STAGING"
    echo "Packaged $DMG"
    ;;
  --install)
    mkdir -p ~/Applications
    pkill -x StockBar || true
    rm -rf ~/Applications/StockBar.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/StockBar.app
    echo "Installed to ~/Applications/StockBar.app"
    ;;
esac
