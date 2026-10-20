#!/bin/zsh
# SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
set -eu
LB_PROJECT_DIR="${0:A:h:h}"
LB_VERSION=24.22.0
mkdir -p "$LB_PROJECT_DIR/vendor"
for LB_ARCH in arm64 x64; do
  LB_ARCHIVE="node-v$LB_VERSION-darwin-$LB_ARCH.tar.gz"
  LB_EXPECTED="$(awk -v name="$LB_ARCHIVE" '$2 == name { print $1 }' "$LB_PROJECT_DIR/node-SHASUMS256.txt")"
  [[ -n "$LB_EXPECTED" ]] || { print -u2 'No pinned checksum'; exit 1; }
  curl --fail --location --proto '=https' --tlsv1.2 --output "$LB_PROJECT_DIR/$LB_ARCHIVE" "https://nodejs.org/dist/v$LB_VERSION/$LB_ARCHIVE"
  LB_ACTUAL="$(shasum -a 256 "$LB_PROJECT_DIR/$LB_ARCHIVE" | awk '{print $1}')"
  [[ "$LB_ACTUAL" == "$LB_EXPECTED" ]] || { print -u2 'Node checksum mismatch'; exit 1; }
  tar -xzf "$LB_PROJECT_DIR/$LB_ARCHIVE" -C "$LB_PROJECT_DIR/vendor"
  if [[ -d "$LB_PROJECT_DIR/vendor/node-$LB_ARCH" ]]; then
    print -u2 "Existing vendor/node-$LB_ARCH; remove or retain it deliberately before replacing."
    exit 1
  fi
  mv "$LB_PROJECT_DIR/vendor/node-v$LB_VERSION-darwin-$LB_ARCH" "$LB_PROJECT_DIR/vendor/node-$LB_ARCH"
done
