#!/bin/bash
# Builds a universal Release copy of Skyward Plus and packs it into a drag-to-install DMG.
# Usage: tools/make-dmg.sh            -> dist/Skyward-Plus-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DERIVED="$ROOT/.build-release"
DIST="$ROOT/dist"
STAGE="$(mktemp -d)/Skyward Plus"
mkdir -p "$STAGE" "$DIST"

echo "› Generating project"
xcodegen generate >/dev/null

echo "› Building Release (Apple silicon + Intel)"
xcodebuild -project SkywardPlus.xcodeproj -scheme SkywardPlus -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO ENABLE_DEBUG_DYLIB=NO CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  -quiet build

APP="$DERIVED/Build/Products/Release/Skyward Plus.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
ARCHS_BUILT=$(lipo -archs "$APP/Contents/MacOS/Skyward Plus")
[[ "$ARCHS_BUILT" == *arm64* && "$ARCHS_BUILT" == *x86_64* ]] || { echo "Expected a universal binary, got: $ARCHS_BUILT"; exit 1; }

echo "› Signing (ad-hoc)"
# Sign nested code first (widget extension, if any), then the app.
find "$APP/Contents" -name "*.appex" -maxdepth 3 -print0 2>/dev/null | while IFS= read -r -d '' ext; do
  codesign --force --sign - --timestamp=none --preserve-metadata=entitlements "$ext"
done
codesign --force --sign - --timestamp=none --preserve-metadata=entitlements "$APP"
codesign --verify --deep --strict "$APP"

echo "› Staging"
ditto "$APP" "$STAGE/Skyward Plus.app"
ln -s /Applications "$STAGE/Applications"
cp "tools/How to Open.txt" "$STAGE/"
cp "tools/Allow Skyward Plus.command" "$STAGE/"
chmod +x "$STAGE/Allow Skyward Plus.command"
mkdir "$STAGE/.background"
xcrun swift tools/dmg-background.swift "$STAGE/.background/bg.png" 1 >/dev/null
xcrun swift tools/dmg-background.swift "$STAGE/.background/bg@2x.png" 2 >/dev/null
tiffutil -cathidpicheck "$STAGE/.background/bg.png" "$STAGE/.background/bg@2x.png" -out "$STAGE/.background/bg.tiff" >/dev/null 2>&1
rm "$STAGE/.background/bg.png" "$STAGE/.background/bg@2x.png"

RW="$(mktemp -d)/rw.dmg"
OUT="$DIST/Skyward-Plus-$VERSION.dmg"
rm -f "$OUT"
hdiutil create -srcfolder "$STAGE" -volname "Skyward Plus" -fs HFS+ -format UDRW -ov "$RW" >/dev/null

echo "› Laying out the window"
DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1}')
VOL="/Volumes/Skyward Plus"
sleep 1
TO=""; command -v timeout >/dev/null && TO="timeout 60"
if ! $TO osascript <<OSA >/dev/null 2>&1
tell application "Finder"
  tell disk "Skyward Plus"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 528}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set text size of opts to 12
    set background picture of opts to file ".background:bg.tiff"
    set position of item "Skyward Plus.app" of container window to {160, 190}
    set position of item "Applications" of container window to {440, 190}
    set position of item "How to Open.txt" of container window to {230, 330}
    set position of item "Allow Skyward Plus.command" of container window to {370, 330}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
then
  echo "  (Finder layout skipped: allow Terminal to control Finder for a nicer window)"
fi
chmod -Rf go-w "$VOL" || true
sync
hdiutil detach "$DEV" -quiet || hdiutil detach "$DEV" -force -quiet

echo "› Compressing"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -f "$RW"
echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
