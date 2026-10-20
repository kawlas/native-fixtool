// SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
export function prepareRuntime() {
  const app = '/Applications/Native Access.app';
  const version = execFileSync(
    '/usr/bin/plutil',
    ['-extract', 'CFBundleShortVersionString', 'raw', app + '/Contents/Info.plist'],
    { encoding: 'utf8' },
  ).trim();
  if (version !== '3.26.0')
    throw Error(
      `Native Access ${version}: this adapter supports 3.26.0. For newer versions use Support → Add Product Content until a verified adapter is available.`,
    );
  const asar = app + '/Contents/Resources/app.asar';
  const b = fs.readFileSync(asar);
  const table = JSON.parse(b.subarray(16, 16 + b.readUInt32LE(12)).toString());
  const base = 8 + b.readUInt32LE(4);
  const hash = crypto.createHash('sha256').update(b).digest('hex');
  const runtime = path.join(
    os.homedir(),
    'Library/Application Support/Library Bridge/runtime',
    hash.slice(0, 16),
  );
  fs.mkdirSync(runtime, { recursive: true });
  function content(q, v) {
    return v.unpacked
      ? fs.readFileSync(asar + '.unpacked/' + q)
      : b.subarray(base + Number(v.offset), base + Number(v.offset) + v.size);
  }
  function walk(d, p = '') {
    for (const [k, v] of Object.entries(d.files || {})) {
      const q = p ? p + '/' + k : k;
      if (v.files) walk(v, q);
      else if (
        ['zeromq', 'cmake-ts', 'node-gyp-build', '@native-instruments/access-ntk-zeromq-node'].some(
          (n) => q.startsWith('node_modules/' + n + '/'),
        )
      ) {
        const out = path.join(runtime, q);
        fs.mkdirSync(path.dirname(out), { recursive: true });
        if (!fs.existsSync(out)) fs.writeFileSync(out, content(q, v));
      }
    }
  }
  walk(table);
  let entry = table;
  for (const k of ['out', 'main', 'index.js']) entry = entry.files[k];
  const s = content('out/main/index.js', entry).toString();
  const begin = s.indexOf('function Ni()'),
    end = s.indexOf('function Ai(', begin),
    codecStart = s.indexOf('function Je()'),
    codecEnd = s.indexOf('const kr=');
  if ([begin, end, codecStart, codecEnd].some((x) => x < 0) || !s.startsWith('const e=Mu;'))
    throw Error('Unrecognised NI adapter format. No registration changes were made.');
  const codec =
    s.slice(begin, end) +
    'function Mu(e,t){e-=348;return Ni()[e]}' +
    s.slice(0, s.indexOf(',function(){')) +
    ';' +
    s.slice(codecStart, codecEnd) +
    '\nmodule.exports=yr;';
  fs.writeFileSync(path.join(runtime, 'codec.cjs'), codec);
  return { runtime, version, asarSha256: hash };
}
