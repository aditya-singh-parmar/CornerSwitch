#!/bin/zsh
# Builds a universal CornerSwitch.app, signed with the stable "CornerSwitch Signing"
# certificate, plus build/CornerSwitch.zip (what the updater downloads) and
# build/CornerSwitch.dmg (first install).
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(cat VERSION)
APP=build/CornerSwitch.app
IDENTITY="CornerSwitch Signing"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
    -framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement -framework Security \
    Sources/*.swift -o "build/CornerSwitch-$arch" 2> >(grep -v libswiftCompatibilityPacks >&2)
done
lipo -create build/CornerSwitch-arm64 build/CornerSwitch-x86_64 -output "$APP/Contents/MacOS/CornerSwitch"
rm build/CornerSwitch-arm64 build/CornerSwitch-x86_64
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CornerSwitch</string>
  <key>CFBundleDisplayName</key><string>CornerSwitch</string>
  <key>CFBundleIdentifier</key><string>com.aditya.cornerswitch</string>
  <key>CFBundleExecutable</key><string>CornerSwitch</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSInputMonitoringUsageDescription</key><string>CornerSwitch talks to your Logitech keyboard and mouse to switch their Easy-Switch channel.</string>
</dict>
</plist>
PLIST

# A stable certificate keeps the code identity the same across builds, so macOS
# keeps the Input Monitoring grant and the updater can verify downloads.
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --deep --timestamp=none --sign "$IDENTITY" "$APP"
else
  echo "warning: '$IDENTITY' not in keychain, signing ad-hoc (updates will be refused)" >&2
  codesign --force --deep --sign - "$APP"
fi

(cd build && ditto -c -k --keepParent CornerSwitch.app CornerSwitch.zip)

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "CornerSwitch" -srcfolder "$STAGE" -ov -format UDZO build/CornerSwitch.dmg
rm -rf "$STAGE"

echo "Built CornerSwitch $VERSION: build/CornerSwitch.app, .zip, .dmg"
