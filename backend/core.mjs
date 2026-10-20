// SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';
import { version } from './native.mjs';
export const hashBytes = (b) => crypto.createHash('sha256').update(b).digest('hex');
export function atomicJSON(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = file + '.' + crypto.randomUUID() + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2), { mode: 0o600, flag: 'wx' });
  fs.renameSync(tmp, file);
}
export function canonicalRoot(input) {
  const root = fs.realpathSync(input);
  if (root === '/' || root === os.homedir() || !fs.statSync(root).isDirectory())
    throw Error('Choose the folder containing your libraries.');
  return root;
}
export function rootIdentity(root) {
  const s = fs.statSync(root);
  return { path: root, device: String(s.dev), inode: String(s.ino) };
}
export function assertRootIdentity(root, expected) {
  if (JSON.stringify(rootIdentity(root)) !== JSON.stringify(expected))
    throw Error('The selected disk or folder changed. Scan again.');
}
export const vaultRoot = (root) => path.join(root, '.library-bridge');
export function safeChild(root, relative) {
  if (path.isAbsolute(relative) || relative.split(/[\\/]/).includes('..'))
    throw Error('Unsafe relative path');
  const p = path.resolve(root, relative);
  if (!p.startsWith(root + path.sep)) throw Error('Path escapes the library');
  return p;
}
export function readDescriptor(file) {
  const fd = fs.openSync(file, 'r');
  try {
    const b = Buffer.alloc(262144),
      n = fs.readSync(fd, b, 0, b.length, 0);
    const s = b.subarray(0, n).toString();
    const get = (k) =>
      s.match(new RegExp('<' + k + '>([^<]*)</' + k + '>'))?.[1]?.replaceAll('&amp;', '&');
    return {
      upid: get('UPID'),
      title: get('Name'),
      snpid: get('SNPID'),
      descriptorHash: hashBytes(b.subarray(0, n)),
    };
  } finally {
    fs.closeSync(fd);
  }
}
function hasPayload(folder) {
  return fs
    .readdirSync(folder, { withFileTypes: true })
    .some(
      (d) =>
        (d.isFile() && /\.(ens|rkplr)$/i.test(d.name)) ||
        (d.isDirectory() &&
          [
            'Instruments',
            'Sounds',
            'Samples',
            'Synthesizers',
            'Ensembles',
            'Effects',
            'Presets',
            'Groups',
          ].includes(d.name) &&
          fs.readdirSync(path.join(folder, d.name)).some((n) => !n.startsWith('.'))),
    );
}
export function inventory(root, products = [], { connected = true } = {}) {
  const rows = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name.startsWith('.')) continue;
    const folder = path.join(root, entry.name);
    let row = {
      id: hashBytes(folder).slice(0, 20),
      folder,
      title: entry.name.replace(/ Library$/, ''),
      state: 'needsReview',
      reason: 'No product descriptor',
      version: '',
      targetVersion: '',
      upid: '',
      selected: false,
      identitySource: '',
      descriptorHash: '',
    };
    try {
      const registered = products.filter(
        (p) =>
          p.type === 'PRODUCT_TYPE_CONTENT' &&
          p.installed &&
          !p.isBroken &&
          p.components?.some(
            (c) => c.name === 'COMPONENT_NAME_CONTENTDIR' && c.currentPath === folder,
          ),
      );
      if (registered.length === 1) {
        const p = registered[0];
        Object.assign(row, {
          title: p.title,
          state: 'registered',
          reason: 'Native Access recognises this exact folder',
          version: version(p.installedVersion),
          targetVersion: version(p.targetVersion),
          upid: p.upid,
          identitySource: 'Native Access',
          activationState: p.activationState,
        });
        rows.push(row);
        continue;
      }
      const descriptors = fs.readdirSync(folder).filter((n) => n.endsWith('.nicnt'));
      if (descriptors.length === 1) {
        const d = readDescriptor(path.join(folder, descriptors[0]));
        Object.assign(row, {
          title: d.title || row.title,
          descriptorHash: d.descriptorHash,
          descriptor: descriptors[0],
          identitySource: d.upid ? 'UPID in .nicnt' : 'SNPID and name in .nicnt',
        });
        if (!connected) {
          row.state = 'offline';
          row.reason = 'Local product identity found; Native Access connection required';
          rows.push(row);
          continue;
        }
        const matches = products.filter(
          (p) =>
            p.type === 'PRODUCT_TYPE_CONTENT' &&
            (d.upid
              ? p.upid === d.upid
              : p.title === d.title &&
                p.licenses?.some((l) => Object.values(l).some((v) => v?.snpid === d.snpid))),
        );
        if (matches.length !== 1) {
          row.reason = 'Product identity could not be matched uniquely';
        } else {
          const p = matches[0];
          Object.assign(row, {
            upid: p.upid,
            title: p.title,
            version: p.installed ? version(p.installedVersion) : '',
            targetVersion: version(p.targetVersion),
            registeredPath:
              p.components?.find((c) => c.name === 'COMPONENT_NAME_CONTENTDIR')?.currentPath || '',
          });
          if (p.installed && !p.isBroken) {
            row.state = 'registeredElsewhere';
            row.reason = 'A working installation is already registered at another location';
          } else if (!p.isOwned) {
            row.state = 'notOwned';
            row.reason = 'Product is not owned by the signed-in account';
          } else if (!hasPayload(folder)) {
            row.reason = 'No recognised content found next to the descriptor';
          } else {
            row.state = 'canLocate';
            row.reason = 'Existing content can be submitted to Native Access for validation';
            row.selected = true;
          }
        }
      } else if (descriptors.length > 1) {
        row.reason = 'Multiple product descriptors; manual review required';
      } else {
        const receiptsDir = path.join(vaultRoot(root), 'receipts');
        const receipts = fs.existsSync(receiptsDir)
          ? fs
              .readdirSync(receiptsDir)
              .filter((n) => n.endsWith('.json'))
              .map((n) => {
                try {
                  return JSON.parse(fs.readFileSync(path.join(receiptsDir, n)));
                } catch {
                  return null;
                }
              })
              .filter((r) => r?.folder === entry.name)
          : [];
        if (receipts.length === 1) {
          const r = receipts[0],
            p = products.find(
              (p) => p.upid === r.upid && p.title === r.title && p.type === 'PRODUCT_TYPE_CONTENT',
            );
          Object.assign(row, {
            title: r.title,
            upid: r.upid,
            version: r.record?.ContentVersion || '',
            identitySource: 'Original installation receipt',
          });
          if (connected && p?.isOwned && !p.installed) {
            row.state = 'receiptAvailable';
            row.reason =
              'Original registration is available; every saved file must pass SHA-256 before restore';
            row.selected = true;
          } else {
            row.state = connected ? 'needsReview' : 'offline';
            row.reason = 'Original registration found; verify ownership and Native Access status';
          }
        } else
          row.reason =
            'This release may legitimately have no .nicnt. It needs an authentic saved receipt or official NI installation verification.';
      }
    } catch (e) {
      row.state = 'needsReview';
      row.reason = String(e.message || e);
    }
    rows.push(row);
  }
  const ids = new Map();
  for (const r of rows.filter((r) => ['canLocate', 'receiptAvailable'].includes(r.state))) {
    const list = ids.get(r.upid) || [];
    list.push(r);
    ids.set(r.upid, list);
  }
  for (const list of ids.values())
    if (list.length > 1)
      for (const row of list) {
        row.state = 'needsReview';
        row.reason =
          'Multiple folders claim the same product identity; choose the correct copy before repair';
        row.selected = false;
      }
  return rows.sort((a, b) => a.title.localeCompare(b.title));
}
export function publicRows(rows) {
  return rows.map((r) => ({ ...r }));
}
export function makePlan(root, rows, connection) {
  return {
    schema: 1,
    date: new Date().toISOString(),
    root: rootIdentity(root),
    nativeVersion: connection.version || '',
    rows: rows
      .filter((r) => ['canLocate', 'receiptAvailable'].includes(r.state))
      .map((r) => ({
        id: r.id,
        folder: r.folder,
        title: r.title,
        upid: r.upid,
        state: r.state,
        descriptor: r.descriptor || '',
        descriptorHash: r.descriptorHash || '',
      })),
  };
}
export function acquireLock(root) {
  const dir = vaultRoot(root);
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, 'operation.lock');
  let fd;
  try {
    fd = fs.openSync(file, 'wx', 0o600);
  } catch (e) {
    if (e.code !== 'EEXIST') throw e;
    let old;
    try {
      old = JSON.parse(fs.readFileSync(file));
    } catch (error) {
      throw Error('Another operation may be starting. Try again shortly.', { cause: error });
    }
    if (old.host !== os.hostname())
      throw Error(
        'This drive has an operation lock from another computer. Inspect .library-bridge/operation.lock before removing it.',
        { cause: e },
      );
    if (!Number.isSafeInteger(old.pid) || old.pid <= 0)
      throw Error('Invalid operation lock. Inspect it before making changes.', { cause: e });
    let alive = true;
    try {
      process.kill(old.pid, 0);
    } catch (error) {
      if (error.code === 'ESRCH') alive = false;
      else
        throw Error('Cannot check the earlier disk operation. Its lock was left in place.', {
          cause: error,
        });
    }
    if (alive)
      throw Error('Another repair or backup is already running for this disk.', { cause: e });
    fs.unlinkSync(file);
    fd = fs.openSync(file, 'wx', 0o600);
  }
  fs.writeFileSync(
    fd,
    JSON.stringify({ pid: process.pid, host: os.hostname(), date: new Date().toISOString() }),
  );
  fs.closeSync(fd);
  return () => {
    try {
      const d = JSON.parse(fs.readFileSync(file));
      if (d.pid === process.pid && d.host === os.hostname()) fs.unlinkSync(file);
    } catch {
      // A missing or changed lock during cleanup must not mask the operation's result.
    }
  };
}
export function parseMetalink(xml) {
  if (!xml.includes('urn:ietf:params:xml:ns:metalink'))
    throw Error('Not an IETF Metalink manifest');
  const decode = (s) =>
    s
      .replace(/&#x([0-9a-f]+);/gi, (_, x) => String.fromCodePoint(parseInt(x, 16)))
      .replace(/&#(\d+);/g, (_, x) => String.fromCodePoint(Number(x)))
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
  const files = [
    ...xml.matchAll(/<(?:\w+:)?file\s+name="([^"]+)"[^>]*>([\s\S]*?)<\/(?:\w+:)?file>/g),
  ].map((m) => {
    const name = decode(m[1]),
      size = Number(m[2].match(/<(?:\w+:)?size>(\d+)<\/(?:\w+:)?size>/)?.[1]),
      sha256 = m[2]
        .match(/<(?:\w+:)?hash\s+type="sha-256"[^>]*>([0-9a-f]{64})<\/(?:\w+:)?hash>/i)?.[1]
        ?.toLowerCase();
    if (!Number.isSafeInteger(size) || size < 0 || !sha256)
      throw Error('Missing size or SHA-256 for ' + name);
    return { name, size, sha256 };
  });
  if (!files.length) throw Error('Empty Metalink manifest');
  return files;
}
export async function hashFile(file, { cancelled = () => false } = {}) {
  const h = crypto.createHash('sha256');
  for await (const b of fs.createReadStream(file, { highWaterMark: 4 * 1024 * 1024 })) {
    if (cancelled()) throw Error('CANCELLED');
    h.update(b);
  }
  return h.digest('hex');
}
export async function verifyFiles(
  root,
  files,
  { progress = () => {}, cancelled = () => false } = {},
) {
  const result = [];
  let bytes = 0;
  for (const [index, f] of files.entries()) {
    if (cancelled()) throw Error('CANCELLED');
    const file = safeChild(root, f.name);
    let state = 'missing';
    if (fs.existsSync(file)) {
      const s = fs.lstatSync(file);
      if (!s.isFile() || fs.realpathSync(file) !== file)
        throw Error('A symlink or non-regular file is present: ' + f.name);
      state =
        s.size !== f.size
          ? 'differentSize'
          : (await hashFile(file, { cancelled })) === f.sha256
            ? 'verified'
            : 'differentHash';
    }
    result.push({ ...f, state });
    if (state === 'verified') bytes += f.size;
    if (index % 20 === 0 || index === files.length - 1)
      progress({
        stage: 'verify',
        title: f.name,
        current: index + 1,
        total: files.length,
        verifiedBytes: bytes,
      });
  }
  return result;
}
