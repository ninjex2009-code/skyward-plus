#!/bin/bash
# Lets macOS open Skyward Plus without the "can't check for malware" block.
APP="/Applications/Skyward Plus.app"
if [ ! -d "$APP" ]; then
  echo "Skyward Plus isn't in Applications yet."
  echo "Drag it onto the Applications folder first, then run this again."
  read -n 1 -s -r -p "Press any key to close."
  exit 1
fi
xattr -dr com.apple.quarantine "$APP" 2>/dev/null
echo "Done. Opening Skyward Plus..."
open "$APP"
sleep 1
