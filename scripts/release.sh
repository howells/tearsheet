#!/bin/bash
# Builds a Developer ID copy, notarises and staples it, and publishes it as a
# GitHub release tagged v<MARKETING_VERSION>.
#
#   ASC_ISSUER_ID=<uuid> scripts/release.sh
#
# Signs in with an App Store Connect API key (Admin role, for the Developer ID
# certificate). ASC_KEY_ID defaults to the first key in ~/.appstoreconnect/private_keys.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID: App Store Connect, Users and Access, Integrations, above the key list}"
KEYS="$HOME/.appstoreconnect/private_keys"
ASC_KEY_ID="${ASC_KEY_ID:-$(ls "$KEYS" | sed -n 's/^AuthKey_\(.*\)\.p8$/\1/p' | head -1)}"
KEY_PATH="$KEYS/AuthKey_$ASC_KEY_ID.p8"
[ -f "$KEY_PATH" ] || { echo "No key at $KEY_PATH" >&2; exit 1; }
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
TAG="v$VERSION"
OUT=build/release
ZIP="$OUT/Tearsheet-$VERSION.zip"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "$TAG already exists; bump MARKETING_VERSION in project.yml" >&2
  exit 1
fi
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash local changes first" >&2; exit 1; }

scripts/test.sh
rm -rf "$OUT"
mkdir -p "$OUT"
xcodegen generate --quiet

xcodebuild archive \
  -project Tearsheet.xcodeproj \
  -scheme Tearsheet \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$OUT/Tearsheet.xcarchive" \
  -quiet \
  "${AUTH[@]}"

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>26GV92ZQ4L</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$OUT/Tearsheet.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" \
  "${AUTH[@]}"

APP="$OUT/export/Tearsheet.app"
codesign --verify --strict --deep "$APP"
codesign -dvv "$APP" 2>&1 | grep -q "Authority=Developer ID Application" \
  || { echo "Export is not signed with Developer ID" >&2; exit 1; }

ditto -c -k --keepParent "$APP" "$OUT/notarise.zip"
xcrun notarytool submit "$OUT/notarise.zip" \
  --key "$KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
  --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

git tag -a "$TAG" -m "Tearsheet $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$ZIP" \
  --title "Tearsheet $VERSION" \
  --notes-file scripts/release-notes.md
echo "Published $TAG"
