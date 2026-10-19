#!/bin/bash
set -euo pipefail
mkdir -p build
trap 'code=$?; if [ "$code" -ne 0 ]; then python3 scripts/annotate_build.py; fi; exit "$code"' EXIT
xcodegen generate | tee build/project.log
xcodebuild -resolvePackageDependencies -project MONO.xcodeproj -scheme MONO | tee build/dependencies.log
xcodebuild -project MONO.xcodeproj -scheme MONO -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build | tee build/device-build.log
xcodebuild -project MONO.xcodeproj -scheme MONO -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/MONO-UNSIGNED.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive | tee build/archive.log

# Discover an available iPhone on the selected SDK's runtime, never a hardcoded UDID.
xcrun simctl list devices available --json > build/simulators.json
python3 - <<'PY' > build/simulator-id
import json
devices=json.load(open('build/simulators.json'))['devices']
options=[]
for runtime, entries in devices.items():
    if 'iOS-26' not in runtime: continue
    for item in entries:
        if item.get('isAvailable') and item['name'].startswith('iPhone'):
            options.append((runtime,item['name'],item['udid']))
print(sorted(options)[-1][2] if options else '')
PY
simulator="$(cat build/simulator-id)"
if [ -n "$simulator" ]; then
  xcodebuild -project MONO.xcodeproj -scheme MONO -configuration Debug \
    -destination "platform=iOS Simulator,id=$simulator" -parallel-testing-enabled NO \
    -resultBundlePath build/MONO-tests.xcresult CODE_SIGNING_ALLOWED=NO test | tee build/tests.log
  echo 'Simulator unit/UI tests: executed; see xcresult for counts.' >> "$GITHUB_STEP_SUMMARY"
else
  xcodebuild -project MONO.xcodeproj -scheme MONO -configuration Debug \
    -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing | tee build/simulator-build.log
  echo '::warning::Simulator execution SKIPPED: no available iOS 26 iPhone runtime; test targets compiled only.'
  echo 'Simulator tests: **SKIPPED**, no compatible runtime. Compilation only.' >> "$GITHUB_STEP_SUMMARY"
fi
mkdir -p build/package/Payload
cp -R build/MONO-UNSIGNED.xcarchive/Products/Applications/MONO.app build/package/Payload/
(cd build/package && zip -qry ../MONO-UNSIGNED-REQUIRES-SIGNING.ipa Payload)
tar -czf build/MONO-UNSIGNED.xcarchive.tar.gz -C build MONO-UNSIGNED.xcarchive
echo 'Artifacts: MONO-UNSIGNED-device (archive + unsigned IPA), MONO-build-logs (logs and test results). Neither unsigned artifact installs directly on iPhone.' >> "$GITHUB_STEP_SUMMARY"
