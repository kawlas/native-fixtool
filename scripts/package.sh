#!/bin/zsh
# SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
set -eu
LB_PROJECT_DIR="${0:A:h:h}"
mkdir -p "$LB_PROJECT_DIR/.build"
LB_STAGE_DIR="$(mktemp -d "$LB_PROJECT_DIR/.build/dmg-stage.XXXXXX")"
trap 'rm -rf "$LB_STAGE_DIR"' EXIT
LB_APP_DIR="$LB_PROJECT_DIR/dist/Native FixTool.app"
[[ -d "$LB_APP_DIR" ]] || { print -u2 'Run build.sh first'; exit 1; }
LB_VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$LB_APP_DIR/Contents/Info.plist")"
ditto "$LB_APP_DIR" "$LB_STAGE_DIR/Native FixTool.app"
ln -sfn /Applications "$LB_STAGE_DIR/Applications"
cp "$LB_PROJECT_DIR/README.md" "$LB_STAGE_DIR/README.md"
cp "$LB_PROJECT_DIR/AGENTS.md" "$LB_STAGE_DIR/AGENTS.md"
cp "$LB_PROJECT_DIR/LICENSE" "$LB_STAGE_DIR/LICENSE.txt"
cp "$LB_PROJECT_DIR/LICENSE" "$LB_STAGE_DIR/LICENSE"
cp "$LB_PROJECT_DIR/INSTRUKCJA.md" "$LB_STAGE_DIR/INSTRUKCJA.md"
cp "$LB_PROJECT_DIR/CZYTAJ NAJPIERW.html" "$LB_STAGE_DIR/CZYTAJ NAJPIERW.html"
cp "$LB_PROJECT_DIR/CHANGELOG.md" "$LB_STAGE_DIR/CHANGELOG.md"
cp "$LB_PROJECT_DIR/VERIFICATION.md" "$LB_STAGE_DIR/VERIFICATION.md"
ditto "$LB_PROJECT_DIR/docs" "$LB_STAGE_DIR/docs"
LB_DMG="$LB_PROJECT_DIR/dist/Native-FixTool-$LB_VERSION-universal.dmg"
if [[ -f "$LB_DMG" ]]; then rm "$LB_DMG"; fi
hdiutil create -volname 'Native FixTool' -srcfolder "$LB_STAGE_DIR" -format UDZO -ov "$LB_DMG"
(
  cd "$LB_PROJECT_DIR/dist"
  shasum -a 256 "Native-FixTool-$LB_VERSION-universal.dmg" > "Native-FixTool-$LB_VERSION-universal.dmg.sha256"
)
print "$LB_DMG"
