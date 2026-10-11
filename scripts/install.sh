#!/bin/bash
# Builds a Release copy and installs it at /Applications/Tearsheet.app, a
# fixed path that launch at login and the Screen Recording grant rely on.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild \
  -project Tearsheet.xcodeproj \
  -scheme Tearsheet \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  -quiet \
  build

osascript -e 'tell application id "com.howells.tearsheet" to quit' 2>/dev/null || true
rm -rf /Applications/Tearsheet.app
ditto build/DerivedData/Build/Products/Release/Tearsheet.app /Applications/Tearsheet.app
open /Applications/Tearsheet.app
echo "Installed /Applications/Tearsheet.app"
