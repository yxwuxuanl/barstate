#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$BUILD_DIR/BarState.app"
SERVICE_DIR="$APP_DIR/Contents/XPCServices/com.barstate.BarState.ScriptService.xpc"
DIRECT_BUILD_DIR="$BUILD_DIR/direct"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"

cd "$PROJECT_DIR"

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
COMMAND_LINE_TOOLS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
if [[ "$SDK_PATH" == *"CommandLineTools"* && -d "$COMMAND_LINE_TOOLS_SDK" ]]; then
    SDK_PATH="$COMMAND_LINE_TOOLS_SDK"
fi

MACHINE_ARCH="$(uname -m)"
TARGET="$MACHINE_ARCH-apple-macosx15.0"
CORE_SOURCES=("$PROJECT_DIR"/Sources/BarStateCore/*.swift)
APP_SOURCES=(
    "$PROJECT_DIR"/Sources/BarState/App/*.swift
    "$PROJECT_DIR"/Sources/BarState/Services/*.swift
    "$PROJECT_DIR"/Sources/BarState/State/*.swift
    "$PROJECT_DIR"/Sources/BarState/Views/*.swift
)
SERVICE_SOURCES=("$PROJECT_DIR"/Sources/BarStateScriptService/*.swift)

/bin/mkdir -p "$DIRECT_BUILD_DIR" "$MODULE_CACHE_DIR"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" swiftc \
    -swift-version 6 \
    -target "$TARGET" \
    -sdk "$SDK_PATH" \
    -O \
    -emit-module \
    -emit-library \
    -static \
    -module-name BarStateCore \
    "${CORE_SOURCES[@]}" \
    -framework JavaScriptCore \
    -emit-module-path "$DIRECT_BUILD_DIR/BarStateCore.swiftmodule" \
    -o "$DIRECT_BUILD_DIR/libBarStateCore.a"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" swiftc \
    -swift-version 6 \
    -target "$TARGET" \
    -sdk "$SDK_PATH" \
    -O \
    -I "$DIRECT_BUILD_DIR" \
    -L "$DIRECT_BUILD_DIR" \
    -lBarStateCore \
    "${APP_SOURCES[@]}" \
    -framework AppKit \
    -framework SwiftUI \
    -framework Network \
    -framework ServiceManagement \
    -framework Combine \
    -framework JavaScriptCore \
    -o "$DIRECT_BUILD_DIR/BarState"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" swiftc \
    -swift-version 6 \
    -target "$TARGET" \
    -sdk "$SDK_PATH" \
    -O \
    -I "$DIRECT_BUILD_DIR" \
    -L "$DIRECT_BUILD_DIR" \
    -lBarStateCore \
    "${SERVICE_SOURCES[@]}" \
    -framework JavaScriptCore \
    -o "$DIRECT_BUILD_DIR/BarStateScriptService"

/bin/rm -rf "$APP_DIR"
/bin/mkdir -p "$APP_DIR/Contents/MacOS"
/bin/mkdir -p "$APP_DIR/Contents/Resources"
/bin/mkdir -p "$SERVICE_DIR/Contents/MacOS"
/bin/mkdir -p "$SERVICE_DIR/Contents/Resources"

/bin/cp "$PROJECT_DIR/Support/BarState-Info.plist" "$APP_DIR/Contents/Info.plist"
/bin/cp "$PROJECT_DIR/Support/BarState.icns" "$APP_DIR/Contents/Resources/BarState.icns"
/bin/cp -R "$PROJECT_DIR/Sources/BarStateCore/Resources/." "$APP_DIR/Contents/Resources/"
/bin/cp "$DIRECT_BUILD_DIR/BarState" "$APP_DIR/Contents/MacOS/BarState"
/bin/cp "$PROJECT_DIR/Support/ScriptService-Info.plist" "$SERVICE_DIR/Contents/Info.plist"
/bin/cp -R "$PROJECT_DIR/Sources/BarStateCore/Resources/." "$SERVICE_DIR/Contents/Resources/"
/bin/cp "$DIRECT_BUILD_DIR/BarStateScriptService" "$SERVICE_DIR/Contents/MacOS/BarStateScriptService"

/usr/bin/codesign --force --sign - \
    --entitlements "$PROJECT_DIR/Support/ScriptService.entitlements" \
    "$SERVICE_DIR"
/usr/bin/codesign --force --sign - \
    --entitlements "$PROJECT_DIR/Support/BarState.entitlements" \
    "$APP_DIR"

echo "$APP_DIR"
