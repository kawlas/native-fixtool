#!/bin/zsh
# SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
set -eu
LB_PROJECT_DIR="${0:A:h:h}"
if [[ $# -ne 2 ]]; then
  print -u2 'Usage: scripts/sign-and-notarize.sh "Developer ID Application: Your Name (TEAMID)" existing-notary-keychain-profile'
  exit 1
fi
LB_SIGN_ID="$1"
LB_NOTARY_PROFILE="$2"
LB_APP_DIR="$LB_PROJECT_DIR/dist/Native FixTool.app"
LB_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$LB_APP_DIR/Contents/Info.plist")"
for LB_ARCH in arm64 x64; do
  codesign --force --timestamp --options runtime --entitlements "$LB_PROJECT_DIR/Node.entitlements.plist" --sign "$LB_SIGN_ID" "$LB_APP_DIR/Contents/Resources/bin/node-$LB_ARCH"
done
codesign --force --timestamp --options runtime --sign "$LB_SIGN_ID" "$LB_APP_DIR"
codesign --verify --deep --strict "$LB_APP_DIR"
"$LB_PROJECT_DIR/scripts/package.sh"
LB_DMG="$LB_PROJECT_DIR/dist/Native-FixTool-$LB_VERSION-universal.dmg"
codesign --timestamp --sign "$LB_SIGN_ID" "$LB_DMG"
xcrun notarytool submit "$LB_DMG" --keychain-profile "$LB_NOTARY_PROFILE" --wait
xcrun stapler staple "$LB_DMG"
xcrun stapler validate "$LB_DMG"
(
  cd "$LB_PROJECT_DIR/dist"
  shasum -a 256 "Native-FixTool-$LB_VERSION-universal.dmg" > "Native-FixTool-$LB_VERSION-universal.dmg.sha256"
)
