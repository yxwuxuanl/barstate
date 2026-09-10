#!/bin/zsh
# Give the built app its own identity for UI/notification checks while the regular app is running.
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
python3 - <<'PY'
from pathlib import Path
import plistlib
import shutil
source = Path('.build/BarState.app')
target = Path('.build/BarState Preview.app')
if target.exists():
    shutil.rmtree(target)
shutil.copytree(source, target)
plist = target / 'Contents/Info.plist'
info = plistlib.loads(plist.read_bytes())
info.update(CFBundleIdentifier='com.barstate.BarState.IterationPreview',
            CFBundleDisplayName='BarState Preview', CFBundleName='BarState Preview')
plist.write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - --entitlements Support/BarState.entitlements '.build/BarState Preview.app'
echo "$PROJECT_DIR/.build/BarState Preview.app"
