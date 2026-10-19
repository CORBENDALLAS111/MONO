#!/bin/bash
set -euo pipefail
mkdir -p build
signing_dir="$RUNNER_TEMP/mono-signing"
mkdir -m 700 -p "$signing_dir"
python3 - <<'PY'
import base64, os, pathlib, secrets
folder=pathlib.Path(os.environ['RUNNER_TEMP'])/'mono-signing'
for variable, name in [('APPLE_P12_BASE64','certificate.p12'),('APP_PROFILE_BASE64','app.mobileprovision'),('EXTENSION_PROFILE_BASE64','share.mobileprovision')]:
    file=folder/name
    file.write_bytes(base64.b64decode(os.environ[variable],validate=True))
    file.chmod(0o600)
(folder/'password').write_text(secrets.token_urlsafe(48))
(folder/'password').chmod(0o600)
PY
security list-keychains -d user > "$signing_dir/original-keychains"
keychain="$signing_dir/mono.keychain-db"
password="$(cat "$signing_dir/password")"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$signing_dir/certificate.p12" -k "$keychain" -P "$APPLE_P12_PASSWORD" -t cert -f pkcs12 -T /usr/bin/codesign -T /usr/bin/security > /dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" > /dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
security cms -D -i "$signing_dir/app.mobileprovision" > "$signing_dir/app.plist"
security cms -D -i "$signing_dir/share.mobileprovision" > "$signing_dir/share.plist"
python3 scripts/validate_signing.py
