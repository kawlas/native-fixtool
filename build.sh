#!/bin/zsh
# SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
set -eu
PROJECT_DIR="${0:A:h}"
mkdir -p "$PROJECT_DIR/.build" "$PROJECT_DIR/dist"
BUILD_STAGE="$(mktemp -d "$PROJECT_DIR/.build/app-stage.XXXXXX")"
trap 'rm -rf "$BUILD_STAGE"' EXIT
APP_DIR="$BUILD_STAGE/Native FixTool.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/bin" "$PROJECT_DIR/.build"
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macosx14.0 -framework AppKit "$PROJECT_DIR/Sources/LibraryBridge.swift" -o "$PROJECT_DIR/.build/LibraryBridge-arm64"
xcrun swiftc -swift-version 5 -parse-as-library -O -target x86_64-apple-macosx14.0 -framework AppKit "$PROJECT_DIR/Sources/LibraryBridge.swift" -o "$PROJECT_DIR/.build/LibraryBridge-x64"
lipo -create "$PROJECT_DIR/.build/LibraryBridge-arm64" "$PROJECT_DIR/.build/LibraryBridge-x64" -output "$APP_DIR/Contents/MacOS/LibraryBridge"
cp -R "$PROJECT_DIR/backend" "$APP_DIR/Contents/Resources/"
cp "$PROJECT_DIR/vendor/node-arm64/bin/node" "$APP_DIR/Contents/Resources/bin/node-arm64"
cp "$PROJECT_DIR/vendor/node-x64/bin/node" "$APP_DIR/Contents/Resources/bin/node-x64"
cp "$PROJECT_DIR/vendor/node-x64/LICENSE" "$APP_DIR/Contents/Resources/Node-LICENSE.txt"
cp "$PROJECT_DIR/LICENSE" "$APP_DIR/Contents/Resources/Library-Bridge-LICENSE.txt"
cp -R "$PROJECT_DIR/Resources/Fonts" "$APP_DIR/Contents/Resources/Fonts"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ -f "$PROJECT_DIR/AppIcon.icns" ]]; then cp "$PROJECT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign - --options runtime --entitlements "$PROJECT_DIR/Node.entitlements.plist" "$APP_DIR/Contents/Resources/bin/node-arm64"
codesign --force --sign - --options runtime --entitlements "$PROJECT_DIR/Node.entitlements.plist" "$APP_DIR/Contents/Resources/bin/node-x64"
codesign --force --sign - --options runtime "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
FINAL_APP="$PROJECT_DIR/dist/Native FixTool.app"
if [[ -e "$FINAL_APP" ]]; then
  [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$FINAL_APP/Contents/Info.plist")" == app.librarybridge.mac ]] || { print -u2 'Unexpected app at output path'; exit 1; }
  mv "$FINAL_APP" "$BUILD_STAGE/previous.app"
fi
mv "$APP_DIR" "$FINAL_APP"
print "$FINAL_APP"
