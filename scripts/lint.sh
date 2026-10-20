#!/bin/zsh
# SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
set -eu
LB_PROJECT_DIR="${0:A:h:h}"
LB_ARCH=arm64
[[ "$(uname -m)" == arm64 ]] || LB_ARCH=x64
LB_NODE="$LB_PROJECT_DIR/vendor/node-$LB_ARCH/bin/node"
[[ -x "$LB_NODE" && -f "$LB_PROJECT_DIR/node_modules/eslint/bin/eslint.js" ]] || { print -u2 'Run scripts/setup-lint.sh first (downloads development tools).'; exit 1; }
cd "$LB_PROJECT_DIR"
"$LB_NODE" node_modules/eslint/bin/eslint.js backend tests eslint.config.mjs --max-warnings 0
"$LB_NODE" node_modules/prettier/bin/prettier.cjs --check backend tests eslint.config.mjs package.json .prettierrc.json
"$LB_NODE" node_modules/prettier/bin/prettier.cjs --check --parser json .swift-format
xcrun swift-format lint --strict --recursive Sources scripts/icon.swift
zsh -n build.sh scripts/*.sh
python3 - <<'PY'
import ast
from pathlib import Path
for script in Path('scripts').glob('*.py'):
    ast.parse(script.read_text(), filename=str(script))
print('Python AST and zsh syntax: OK')
PY
print 'Lint passed: ESLint, Prettier, swift-format, zsh/Python syntax.'
