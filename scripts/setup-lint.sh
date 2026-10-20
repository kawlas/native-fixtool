#!/bin/zsh
# SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
set -eu
LB_PROJECT_DIR="${0:A:h:h}"
LB_ARCH=arm64
[[ "$(uname -m)" == arm64 ]] || LB_ARCH=x64
LB_NODE="$LB_PROJECT_DIR/vendor/node-$LB_ARCH/bin/node"
LB_NPM="$LB_PROJECT_DIR/vendor/node-$LB_ARCH/lib/node_modules/npm/bin/npm-cli.js"
[[ -x "$LB_NODE" && -f "$LB_NPM" ]] || { print -u2 'Run scripts/fetch-node.sh first.'; exit 1; }
cd "$LB_PROJECT_DIR"
"$LB_NODE" --dns-result-order=ipv4first "$LB_NPM" ci --ignore-scripts --no-audit --no-fund
