#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
BUILD_DIR="$PROJECT_DIR/.build"
DIRECT_BUILD_DIR="$BUILD_DIR/direct"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
TEST_BINARY="$DIRECT_BUILD_DIR/BarStateAppSmokeTests"

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
COMMAND_LINE_TOOLS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
if [[ "$SDK_PATH" == *"CommandLineTools"* && -d "$COMMAND_LINE_TOOLS_SDK" ]]; then
    SDK_PATH="$COMMAND_LINE_TOOLS_SDK"
fi

MACHINE_ARCH="$(uname -m)"
TARGET="$MACHINE_ARCH-apple-macosx15.0"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" swiftc \
    -swift-version 6 \
    -target "$TARGET" \
    -sdk "$SDK_PATH" \
    -parse-as-library \
    -I "$DIRECT_BUILD_DIR" \
    -L "$DIRECT_BUILD_DIR" \
    -lBarStateCore \
    "$PROJECT_DIR/Sources/BarState/Services/PollingEngine.swift" \
    "$PROJECT_DIR/Sources/BarState/Services/APIClient.swift" \
    "$PROJECT_DIR/Sources/BarState/Services/ScriptServiceClient.swift" \
    "$PROJECT_DIR/Sources/BarState/State/PersistenceController.swift" \
    "$PROJECT_DIR/Sources/BarState/State/MonitorStore.swift" \
    "$PROJECT_DIR/Tests/BarStateAppSmokeTests/SmokeMain.swift" \
    -framework Combine \
    -framework JavaScriptCore \
    -o "$TEST_BINARY"

BARSTATE_RESOURCE_BUNDLE_PATH="$BUILD_DIR/BarState.app" \
    BARSTATE_PRESET_LANGUAGE=en \
    "$TEST_BINARY" -AppleLanguages '(en)'
BARSTATE_RESOURCE_BUNDLE_PATH="$BUILD_DIR/BarState.app" \
    BARSTATE_PRESET_LANGUAGE=zh-Hans \
    "$TEST_BINARY" -AppleLanguages '(zh-Hans)'
