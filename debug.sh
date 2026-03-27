#!/bin/bash
set -e

APP_NAME="Shelf"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
ICON_SVG="resources/shelf.svg"

find_sdk() {
    local tmp="/tmp/shelf_sdk_check_$$.swift"
    printf 'let _=0\n' > "$tmp"

    local default_sdk
    default_sdk="$(xcrun --show-sdk-path 2>/dev/null)"

    if swiftc -sdk "$default_sdk" -typecheck "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        echo "$default_sdk"
        return
    fi

    local sdk_dir
    sdk_dir="$(dirname "$default_sdk")"

    for sdk in $(ls -rd "$sdk_dir"/MacOSX[0-9]*.sdk 2>/dev/null); do
        if swiftc -sdk "$sdk" -typecheck "$tmp" 2>/dev/null; then
            rm -f "$tmp"
            echo "$sdk"
            return
        fi
    done

    rm -f "$tmp"
    echo "Error: no macOS SDK compatible with installed Swift compiler" >&2
    exit 1
}

MACOS_SDK="$(find_sdk)"

pkill -f "Shelf.app" 2>/dev/null || true

rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

# Build Rust core
(cd core && cargo build --release)

# Generate icon
core/target/release/shelf-icon "$ICON_SVG" "$CONTENTS/Resources/AppIcon.icns" --nearest-neighbor

# Build Swift
swiftc \
    -target arm64-apple-macosx14.0 \
    -sdk "$MACOS_SDK" \
    -import-objc-header bridge/shelf_core.h \
    -L core/target/release \
    -lshelf_core \
    -framework Cocoa \
    -framework SwiftUI \
    -framework Carbon \
    -framework UniformTypeIdentifiers \
    -framework ServiceManagement \
    -framework Quartz \
    -g -Onone \
    -D DEBUG \
    -o "$CONTENTS/MacOS/$APP_NAME" \
    src/*.swift

cp resources/Info.plist "$CONTENTS/"

codesign --force --sign "${MACOS_SIGNING_IDENTITY:--}" "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
open "$APP_BUNDLE"
