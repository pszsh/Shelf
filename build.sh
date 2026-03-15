#!/bin/bash
set -e

APP_NAME="Shelf"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
ICON_SVG="resources/shelf.svg"

rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

# Build Rust core
(cd core && cargo build --release)

# Generate icon
core/target/release/shelf-icon "$ICON_SVG" "$CONTENTS/Resources/AppIcon.icns" --nearest-neighbor

# Build Swift
swiftc \
    -target arm64-apple-macosx14.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -import-objc-header bridge/shelf_core.h \
    -L core/target/release \
    -lshelf_core \
    -framework Cocoa \
    -framework SwiftUI \
    -framework Carbon \
    -framework UniformTypeIdentifiers \
    -framework ServiceManagement \
    -framework Quartz \
    -O \
    -o "$CONTENTS/MacOS/$APP_NAME" \
    src/*.swift

cp resources/Info.plist "$CONTENTS/"

codesign --force --sign "${MACOS_SIGNING_IDENTITY:--}" "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
