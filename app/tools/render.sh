#!/bin/bash
# Renders every screen with the demo student. Usage: tools/render.sh <outdir> [--dark] [--bg <theme>] [--only <name>]
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/sp-shots}"; shift || true
xcodebuild -project SkywardPlus.xcodeproj -scheme SkywardPlus -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build -quiet build 2>&1 | grep -E "error:" && exit 1
HOME_DIR="$(mktemp -d)"; rm -rf "$OUT"; mkdir -p "$OUT"
SKYWARDPLUS_HOME="$HOME_DIR" timeout 240 ".build/Build/Products/Debug/Skyward Plus.app/Contents/MacOS/Skyward Plus" --render-screens "$OUT" "$@" >/dev/null 2>&1
echo "$(ls "$OUT" | wc -l | tr -d ' ') files in $OUT"
