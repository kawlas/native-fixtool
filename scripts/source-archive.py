#!/usr/bin/env python3
# SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
"""Package reviewed source/docs only; exclude private scans, runtime and builds."""
from pathlib import Path
import plistlib
import zipfile

project = Path(__file__).resolve().parent.parent
version = plistlib.loads((project / 'Info.plist').read_bytes())['CFBundleShortVersionString']
files = [project / name for name in [
    'README.md', 'INSTRUKCJA.md', 'CZYTAJ NAJPIERW.html', 'VERIFICATION.md',
    'CHANGELOG.md', 'LICENSE', 'Info.plist', 'build.sh', 'Node.entitlements.plist',
    'Resources/Fonts/Roboto.ttf', 'Resources/Fonts/OFL.txt', 'Resources/Fonts/README.md',
    'node-SHASUMS256.txt', 'AppIcon.icns', '.gitignore', '.design/brief.md',
    'package.json', 'package-lock.json', 'eslint.config.mjs', '.prettierrc.json', '.swift-format',
]]
for directory, suffixes in {
    'Sources': {'.swift'}, 'backend': {'.mjs'}, 'tests': {'.mjs'},
    'scripts': {'.sh', '.swift', '.py'}, 'docs': {'.md'},
}.items():
    files.extend(p for p in (project / directory).rglob('*') if p.is_file() and p.suffix in suffixes)

for file in files:
    if file.is_symlink() or not file.is_file():
        raise RuntimeError('Missing or unexpected source file: ' + str(file))

output = project / 'dist' / f'Native-FixTool-{version}-source.zip'
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(files):
        archive.write(file, 'Native-FixTool/' + file.relative_to(project).as_posix())
print(f'{output} ({len(files)} files)')
