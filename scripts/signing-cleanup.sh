#!/bin/bash
set -euo pipefail
python3 - <<'PY'
import json, os, pathlib, shlex, subprocess
folder=pathlib.Path(os.environ['RUNNER_TEMP'])/'mono-signing'
if not folder.exists(): raise SystemExit()
original=folder/'original-keychains'
if original.exists():
    paths=shlex.split(original.read_text())
    subprocess.run(['security','list-keychains','-d','user','-s',*paths],check=True)
keychain=folder/'mono.keychain-db'
if keychain.exists(): subprocess.run(['security','delete-keychain',str(keychain)],check=True)
installed=folder/'installed.json'
if installed.exists():
    for raw in json.loads(installed.read_text()):
        path=pathlib.Path(raw)
        allowed=[pathlib.Path.home()/'Library/Developer/Xcode/UserData/Provisioning Profiles',pathlib.Path.home()/'Library/MobileDevice/Provisioning Profiles']
        assert path.parent in allowed and path.suffix == '.mobileprovision'
        path.unlink(missing_ok=True)
# Delete only the known files produced by this job; no recursive shell deletion.
for file in folder.iterdir():
    if file.is_file(): file.unlink()
folder.rmdir()
pathlib.Path('signing-project.json').unlink(missing_ok=True)
PY
