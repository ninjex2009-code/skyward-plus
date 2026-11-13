#!/bin/bash
# Builds the iPhone app as an IPA for AltStore / SideStore: dist/Skyward-Plus-<version>.ipa
# It's signed ad hoc with its entitlements (the app group the widgets share), which
# AltStore and SideStore read and re-sign with the installer's own certificate.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DERIVED="$ROOT/.build-ios-release"
GROUP="group.com.skywardplus.app"

xcodegen generate >/dev/null
xcodebuild -project SkywardPlus.xcodeproj -scheme SkywardPlus -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO -quiet build

APP=$(ls -d "$DERIVED"/Build/Products/Release-iphoneos/*.app | head -1)
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist")
ENT=$(mktemp)
cat > "$ENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.application-groups</key><array><string>$GROUP</string></array>
</dict></plist>
PLIST
for ext in "$APP"/PlugIns/*.appex; do
  [ -e "$ext" ] && codesign --force --sign - --timestamp=none --entitlements "$ENT" "$ext"
done
codesign --force --sign - --timestamp=none --entitlements "$ENT" "$APP"
rm -f "$ENT"

STAGE=$(mktemp -d)
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
mkdir -p dist
OUT="$ROOT/dist/Skyward-Plus-$VERSION.ipa"
rm -f "$OUT"
(cd "$STAGE" && zip -qr "$OUT" Payload)
rm -rf "$STAGE"
echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
