#!/bin/zsh
# Compatibility runner for mixed Command Line Tools installations. CI with Xcode uses swift test.
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
TEST_SDK="${BARSTATE_TEST_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
CLT_DIR="/Library/Developer/CommandLineTools"
if [[ ! -d "$TEST_SDK" || "$(xcode-select -p)" != "$CLT_DIR" ]]; then
    exec swift test "$@"
fi

# The installed private manifest interface can be older than its dylib. Compile the public
# interface in a project-local directory, leaving the system toolchain untouched.
python3 - <<'PY'
from pathlib import Path
import shutil
source = Path('/Library/Developer/CommandLineTools/usr/lib/swift/pm')
target = Path('.build/toolchain-libs')
target.mkdir(parents=True, exist_ok=True)
for entry in source.iterdir():
    if entry.name == 'ManifestAPI':
        continue
    destination = target / entry.name
    if not destination.exists():
        destination.symlink_to(entry, target_is_directory=entry.is_dir())
manifest = target / 'ManifestAPI'
manifest.mkdir(exist_ok=True)
for entry in (source / 'ManifestAPI').iterdir():
    destination = manifest / entry.name
    if entry.is_dir():
        destination.mkdir(exist_ok=True)
        for interface in entry.glob('*.swiftinterface'):
            if '.private.' not in interface.name:
                shutil.copy2(interface, destination / interface.name)
    elif entry.suffix == '.dylib' and not destination.exists():
        destination.symlink_to(entry)
PY

exec env CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
    SWIFTPM_CUSTOM_LIBS_DIR="$PWD/.build/toolchain-libs" \
    swift test --build-system native --disable-sandbox \
    --cache-path .build/swiftpm-cache --manifest-cache none --sdk "$TEST_SDK" \
    -Xswiftc -F -Xswiftc "$CLT_DIR/Library/Developer/Frameworks" \
    -Xswiftc -plugin-path -Xswiftc "$CLT_DIR/usr/lib/swift/host/plugins/testing" \
    -Xlinker -rpath -Xlinker "$CLT_DIR/Library/Developer/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT_DIR/Library/Developer/usr/lib" "$@"
