#!/bin/bash
set -euo pipefail
trap 'code=$?; if [ "$code" -ne 0 ]; then python3 scripts/annotate_build.py; fi; exit "$code"' EXIT
xcodegen generate --spec signing-project.json | tee build/release-project.log
xcodebuild -project MONO.xcodeproj -scheme MONO -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/MONO-SIGNED.xcarchive \
  APP_GROUP="$APP_GROUP" APP_BUNDLE_ID="$APP_BUNDLE_ID" EXTENSION_BUNDLE_ID="$EXTENSION_BUNDLE_ID" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" archive | tee build/release-archive.log
xcodebuild -exportArchive -archivePath build/MONO-SIGNED.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/signed | tee build/export.log
app=build/MONO-SIGNED.xcarchive/Products/Applications/MONO.app
codesign --verify --deep --strict "$app"
test -n "$(find build/signed -name '*.ipa' -print -quit)"
echo "Signed export produced for $EXPORT_METHOD. Installation eligibility still depends on the profiles and registered devices." >> "$GITHUB_STEP_SUMMARY"
