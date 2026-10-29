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
# Builds made outside GitHub Actions are dev builds: they show tools a release hides (Settings → Setup guide).
DEV_BUILD=$([[ -n "${GITHUB_ACTIONS:-}" ]] && echo false || echo true)
# macOS wants a numeric version in the app; a pre-release like 3.0.0-beta-1 keeps its suffix in the tag, the DMG name
# and StockBarVersion (read by the updater, so a beta is offered the next beta).
SHORT_VERSION="${VERSION%%-*}"

# llama.cpp (the AI tab's on-device model), pinned to a release and its checksum. Kept out of git: 150 MB.
LLAMA_RELEASE=b11624
LLAMA_SHA256=a6dd8a5ce837600544320a198f0550d74902f4fce543a00b4e157540235f03df
if [[ "$(cat Vendor/llama.release 2>/dev/null)" != "$LLAMA_RELEASE" ]]; then
  echo "Fetching llama.cpp $LLAMA_RELEASE"
  rm -rf Vendor/llama.xcframework Vendor/llama.zip Vendor/llama-unzip
  mkdir -p Vendor
  curl -fsSL -o Vendor/llama.zip "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_RELEASE/llama-$LLAMA_RELEASE-xcframework.zip"
  echo "$LLAMA_SHA256  Vendor/llama.zip" | shasum -a 256 -c --quiet
  unzip -q Vendor/llama.zip -d Vendor/llama-unzip
  mv Vendor/llama-unzip/build-apple/llama.xcframework Vendor/llama.xcframework
  rm -rf Vendor/llama.zip Vendor/llama-unzip
  echo "$LLAMA_RELEASE" > Vendor/llama.release
fi

# One build per architecture, merged into a universal binary (multi-arch in one step needs full Xcode).
for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx15.0"
done

APP=build/StockBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
lipo -create \
  .build/arm64-apple-macosx/release/StockBar \
  .build/x86_64-apple-macosx/release/StockBar \
  -output "$APP/Contents/MacOS/StockBar"
ditto Vendor/llama.xcframework/macos-arm64_x86_64/llama.framework "$APP/Contents/Frameworks/llama.framework"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Translations: <lang>.lproj/Localizable.strings, looked up from the main bundle by SwiftUI and String(localized:).
cp -R Resources/*.lproj Resources/AI "$APP/Contents/Resources/"

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
  <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>StockBarVersion</key><string>$VERSION</string>
  <key>StockBarDevBuild</key><$DEV_BUILD/>
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
if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  echo "No '$IDENTITY' certificate: signing ad hoc (Keychain access will be asked again after each build)"
  IDENTITY=-
fi
# The framework first: the app's signature covers it, and the updater checks both.
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/llama.framework"
codesign --force --sign "$IDENTITY" "$APP"
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
