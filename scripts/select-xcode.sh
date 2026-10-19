#!/bin/bash
set -euo pipefail
mkdir -p build
# Prefer 26.6 only when actually installed; otherwise newest non-beta stable 26.x.
python3 - <<'PY' > build/developer-dir
import glob, os, re, subprocess
choices=[]
for app in glob.glob('/Applications/Xcode*.app'):
    path=app+'/Contents/Developer'
    if not os.path.isdir(path) or 'beta' in app.lower(): continue
    text=subprocess.check_output(['env','DEVELOPER_DIR='+path,'xcodebuild','-version'],text=True)
    m=re.search(r'Xcode (26(?:\.\d+)+)',text)
    if m:
        version=tuple(map(int,m[1].split('.')))
        choices.append((version[:2] == (26,6),version,path))
if not choices: raise SystemExit('No stable Xcode 26.x installed; refusing an unverified SDK')
print(sorted(choices)[-1][2])
PY
export DEVELOPER_DIR="$(cat build/developer-dir)"
echo "DEVELOPER_DIR=$DEVELOPER_DIR" >> "$GITHUB_ENV"
xcodebuild -version | tee build/xcode-version.txt
xcodebuild -showsdks | tee build/sdks.txt
