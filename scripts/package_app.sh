#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SDK_PATH="${TASKDECK_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
BUILD_CACHE="$PROJECT_ROOT/.build/cache"
MODULE_CACHE="$PROJECT_ROOT/.build/module-cache"
OUTPUT_DIR="$PROJECT_ROOT/outputs"
APP_BUNDLE="$OUTPUT_DIR/TaskDeck.app"
ZIP_FILE="$OUTPUT_DIR/TaskDeck-macOS.zip"
WIDGET_BUNDLE="$APP_BUNDLE/Contents/PlugIns/TaskDeckWidget.appex"

mkdir -p "$BUILD_CACHE" "$MODULE_CACHE" "$OUTPUT_DIR"

env SDKROOT="$SDK_PATH" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    swift build -c release --disable-sandbox --cache-path "$BUILD_CACHE" \
    -Xswiftc -module-cache-path -Xswiftc "$MODULE_CACHE"

BIN_DIR=$(env SDKROOT="$SDK_PATH" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    swift build -c release --show-bin-path --disable-sandbox --cache-path "$BUILD_CACHE")

rm -rf "$APP_BUNDLE"
mkdir -p \
    "$APP_BUNDLE/Contents/MacOS" \
    "$APP_BUNDLE/Contents/Resources" \
    "$WIDGET_BUNDLE/Contents/MacOS"
cp "$BIN_DIR/TaskDeck" "$APP_BUNDLE/Contents/MacOS/TaskDeck"
cp "$PROJECT_ROOT/Assets/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

env SDKROOT="$SDK_PATH" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    swiftc \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macosx14.0 \
    -application-extension \
    -parse-as-library \
    -O \
    -whole-module-optimization \
    -module-name TaskDeckWidget \
    -module-cache-path "$MODULE_CACHE" \
    "$PROJECT_ROOT/Sources/TaskDeck/Localization.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/TaskItem.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/FocusModels.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/TaskDatabase.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/TaskDeckArchive.swift" \
    "$PROJECT_ROOT/Sources/TaskDeck/SharedTaskAccess.swift" \
    "$PROJECT_ROOT/WidgetExtension/TaskDeckWidget.swift" \
    -o "$WIDGET_BUNDLE/Contents/MacOS/TaskDeckWidget"
cp "$PROJECT_ROOT/WidgetExtension/Info.plist" "$WIDGET_BUNDLE/Contents/Info.plist"

ICON_WORK=$(mktemp -d)
trap 'rm -rf "$ICON_WORK"' EXIT
ICONSET="$ICON_WORK/AppIcon.iconset"
MASTER_ICON="$ICON_WORK/master.png"
mkdir -p "$ICONSET"

env SDKROOT="$SDK_PATH" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    swift "$PROJECT_ROOT/scripts/make_icon.swift" "$MASTER_ICON"

for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"; do
    size=${spec%% *}
    name=${spec#* }
    sips -z "$size" "$size" "$MASTER_ICON" --out "$ICONSET/$name" >/dev/null
done

env SDKROOT="$SDK_PATH" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    swift "$PROJECT_ROOT/scripts/pack_icns.swift" \
    "$APP_BUNDLE/Contents/Resources/AppIcon.icns" \
    icp4 "$ICONSET/icon_16x16.png" \
    icp5 "$ICONSET/icon_32x32.png" \
    icp6 "$ICONSET/icon_32x32@2x.png" \
    ic07 "$ICONSET/icon_128x128.png" \
    ic08 "$ICONSET/icon_256x256.png" \
    ic09 "$ICONSET/icon_512x512.png" \
    ic10 "$ICONSET/icon_512x512@2x.png"
codesign --force --sign - \
    --entitlements "$PROJECT_ROOT/Assets/TaskDeckWidget.entitlements" \
    "$WIDGET_BUNDLE"
codesign --force --sign - \
    --entitlements "$PROJECT_ROOT/Assets/TaskDeck.entitlements" \
    "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

rm -f "$ZIP_FILE"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_FILE"

echo "$APP_BUNDLE"
echo "$ZIP_FILE"
