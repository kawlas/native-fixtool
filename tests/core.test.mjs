// SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  inventory,
  hashBytes,
  parseMetalink,
  verifyFiles,
  rootIdentity,
  assertRootIdentity,
  makePlan,
  acquireLock,
  vaultRoot,
} from '../backend/core.mjs';
import { saveReceipts, restoreReceipt, recordPath } from '../backend/vault.mjs';
function fixture() {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'library-bridge-test-')));
  return { root, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}

test('a permission error checking another process never removes its lock', (t) => {
  const f = fixture();
  try {
    fs.mkdirSync(vaultRoot(f.root));
    const file = path.join(vaultRoot(f.root), 'operation.lock');
    const original = JSON.stringify({ pid: 987654, host: os.hostname() });
    fs.writeFileSync(file, original);
    t.mock.method(process, 'kill', () => {
      throw Object.assign(Error('not permitted'), { code: 'EPERM' });
    });
    assert.throws(() => acquireLock(f.root), /lock was left in place/);
    assert.equal(fs.readFileSync(file, 'utf8'), original);
  } finally {
    t.mock.restoreAll();
    f.cleanup();
  }
});

test('a confirmed dead local process permits reclaiming its stale lock', (t) => {
  const f = fixture();
  try {
    fs.mkdirSync(vaultRoot(f.root));
    const file = path.join(vaultRoot(f.root), 'operation.lock');
    fs.writeFileSync(file, JSON.stringify({ pid: 987654, host: os.hostname() }));
    t.mock.method(process, 'kill', () => {
      throw Object.assign(Error('no such process'), { code: 'ESRCH' });
    });
    const release = acquireLock(f.root);
    assert.equal(JSON.parse(fs.readFileSync(file)).pid, process.pid);
    release();
    assert.equal(fs.existsSync(file), false);
  } finally {
    t.mock.restoreAll();
    f.cleanup();
  }
});

test('malformed PID locks fail closed without signalling a process group', () => {
  const f = fixture();
  try {
    fs.mkdirSync(vaultRoot(f.root));
    const file = path.join(vaultRoot(f.root), 'operation.lock');
    for (const pid of [-1, 0, null, '123']) {
      const original = JSON.stringify({ pid, host: os.hostname() });
      fs.writeFileSync(file, original);
      assert.throws(() => acquireLock(f.root), /Invalid operation lock/);
      assert.equal(fs.readFileSync(file, 'utf8'), original);
    }
  } finally {
    f.cleanup();
  }
});
function library(root, name, xml) {
  const folder = path.join(root, name);
  fs.mkdirSync(folder);
  fs.mkdirSync(path.join(folder, 'Instruments'));
  fs.writeFileSync(path.join(folder, 'Instruments', 'test.nki'), 'actual content');
  if (xml) fs.writeFileSync(path.join(folder, name + '.nicnt'), xml);
  return folder;
}
const product = {
  upid: 'product-1',
  title: 'Test Library',
  type: 'PRODUCT_TYPE_CONTENT',
  isOwned: true,
  installed: false,
  installedVersion: {},
  targetVersion: { major: 1 },
  licenses: [],
};
const descriptor =
  '<ProductHints><Product><UPID>product-1</UPID><Name>Test Library</Name><SNPID>001</SNPID></Product></ProductHints>';
test('matches exact UPID; requires actual payload and account ownership', () => {
  const f = fixture();
  try {
    const folder = library(f.root, 'Test', descriptor);
    assert.equal(inventory(f.root, [product])[0].state, 'canLocate');
    assert.equal(inventory(f.root, [{ ...product, isOwned: false }])[0].state, 'notOwned');
    fs.rmSync(path.join(folder, 'Instruments'), { recursive: true });
    assert.equal(inventory(f.root, [product])[0].state, 'needsReview');
  } finally {
    f.cleanup();
  }
});
test('legacy descriptor requires matching name AND licensed SNPID', () => {
  const f = fixture();
  try {
    library(f.root, 'Legacy', '<Name>Test Library</Name><SNPID>001</SNPID>');
    assert.equal(inventory(f.root, [product])[0].state, 'needsReview');
    assert.equal(
      inventory(f.root, [{ ...product, licenses: [{ perpetualStandalone: { snpid: '001' } }] }])[0]
        .state,
      'canLocate',
    );
    assert.equal(
      inventory(f.root, [{ ...product, licenses: [{ perpetualStandalone: { snpid: '999' } }] }])[0]
        .state,
      'needsReview',
    );
  } finally {
    f.cleanup();
  }
});
test('duplicate product identities are not silently registered twice', () => {
  const f = fixture();
  try {
    library(f.root, 'Copy A', descriptor);
    library(f.root, 'Copy B', descriptor);
    assert.ok(inventory(f.root, [product]).every((r) => r.state === 'needsReview'));
  } finally {
    f.cleanup();
  }
});
test('existing working installation elsewhere is preserved', () => {
  const f = fixture();
  try {
    library(f.root, 'Test', descriptor);
    const rows = inventory(f.root, [
      {
        ...product,
        installed: true,
        components: [{ name: 'COMPONENT_NAME_CONTENTDIR', currentPath: '/other/working/path' }],
      },
    ]);
    assert.equal(rows[0].state, 'registeredElsewhere');
    assert.equal(makePlan(f.root, rows, { version: '3.26.0' }).rows.length, 0);
  } finally {
    f.cleanup();
  }
});
test('offline inventory identifies local content without claiming NI installation', () => {
  const f = fixture();
  try {
    library(f.root, 'Test', descriptor);
    assert.equal(inventory(f.root, [], { connected: false })[0].state, 'offline');
  } finally {
    f.cleanup();
  }
});
test('root identity rejects replaced disks/folders', () => {
  const f = fixture();
  try {
    const identity = rootIdentity(f.root);
    assert.doesNotThrow(() => assertRootIdentity(f.root, identity));
    assert.throws(() => assertRootIdentity(f.root, { ...identity, inode: '0' }), /changed/);
  } finally {
    f.cleanup();
  }
});
test('manifest verifies bytes, detects same-length changes and rejects traversal', async () => {
  const f = fixture();
  try {
    fs.writeFileSync(path.join(f.root, 'a & b.wav'), 'good');
    const xml = `<metalink xmlns="urn:ietf:params:xml:ns:metalink"><file name="a &amp; b.wav"><size>4</size><hash type="sha-256">${hashBytes('good')}</hash></file></metalink>`;
    const files = parseMetalink(xml);
    assert.equal((await verifyFiles(f.root, files))[0].state, 'verified');
    fs.writeFileSync(path.join(f.root, 'a & b.wav'), 'evil');
    assert.equal((await verifyFiles(f.root, files))[0].state, 'differentHash');
    fs.unlinkSync(path.join(f.root, 'a & b.wav'));
    assert.equal((await verifyFiles(f.root, files))[0].state, 'missing');
    await assert.rejects(verifyFiles(f.root, [{ ...files[0], name: '../outside' }]), /Unsafe/);
  } finally {
    f.cleanup();
  }
});
test('symlinks cannot escape manifest verification', async () => {
  const f = fixture();
  try {
    fs.symlinkSync('/etc/hosts', path.join(f.root, 'link'));
    await assert.rejects(
      verifyFiles(f.root, [{ name: 'link', size: 4, sha256: hashBytes('good') }]),
      /symlink/,
    );
  } finally {
    f.cleanup();
  }
});
test('cancellation is checked before hashing more files', async () => {
  const f = fixture();
  try {
    await assert.rejects(
      verifyFiles(f.root, [{ name: 'missing', size: 0, sha256: hashBytes('') }], {
        cancelled: () => true,
      }),
      /CANCELLED/,
    );
  } finally {
    f.cleanup();
  }
});
test('operation lock prevents concurrent mutations', () => {
  const f = fixture();
  try {
    const release = acquireLock(f.root);
    assert.throws(() => acquireLock(f.root), /already running/);
    release();
    const release2 = acquireLock(f.root);
    release2();
  } finally {
    f.cleanup();
  }
});
test('authentic receipt restores original version only after all hashes match; never overwrites', async () => {
  const f = fixture();
  try {
    const folder = library(f.root, 'Without Descriptor', null);
    const records = path.join(f.root, 'mock-system-records');
    fs.mkdirSync(records);
    const p = {
      ...product,
      title: 'No Descriptor',
      installed: true,
      isBroken: false,
      activationState: 'ACTIVATION_STATE_ACTIVATED',
      installedVersion: { major: 1, minor: 2, micro: 3 },
      targetVersion: { major: 99 },
      components: [{ name: 'COMPONENT_NAME_CONTENTDIR', currentPath: folder }],
    };
    fs.writeFileSync(
      recordPath(p.title, records),
      JSON.stringify({ ContentDir: folder, ContentVersion: '1.2.3' }),
    );
    const saved = await saveReceipts(f.root, [p], { recordsRoot: records });
    assert.equal(saved[0].state, 'saved');
    fs.unlinkSync(recordPath(p.title, records));
    const row = { upid: p.upid, folder, title: p.title };
    const restored = await restoreReceipt(
      f.root,
      row,
      { ...p, installed: false },
      { recordsRoot: records },
    );
    const record = JSON.parse(fs.readFileSync(recordPath(p.title, records)));
    assert.equal(record.ContentVersion, '1.2.3');
    assert.notEqual(record.ContentVersion, '99.0.0');
    await assert.rejects(
      restoreReceipt(f.root, row, { ...p, installed: false }, { recordsRoot: records }),
      /already exists/,
    );
    restored.rollback();
    fs.writeFileSync(path.join(folder, 'Instruments/test.nki'), 'changed bytes');
    await assert.rejects(
      restoreReceipt(f.root, row, { ...p, installed: false }, { recordsRoot: records }),
      /Files differ/,
    );
    assert.equal(fs.existsSync(recordPath(p.title, records)), false);
  } finally {
    f.cleanup();
  }
});
test('descriptor-only backup cannot fabricate a full verified receipt', async () => {
  const f = fixture();
  try {
    const folder = library(f.root, 'With Descriptor', descriptor);
    const records = path.join(f.root, 'mock-records');
    fs.mkdirSync(records);
    const p = {
      ...product,
      installed: true,
      activationState: 'ACTIVATION_STATE_ACTIVATED',
      components: [{ name: 'COMPONENT_NAME_CONTENTDIR', currentPath: folder }],
    };
    fs.writeFileSync(
      recordPath(p.title, records),
      JSON.stringify({ ContentDir: folder, ContentVersion: '1.0.0' }),
    );
    await saveReceipts(f.root, [p], { recordsRoot: records });
    fs.unlinkSync(recordPath(p.title, records));
    await assert.rejects(
      restoreReceipt(
        f.root,
        { upid: p.upid, folder },
        { ...p, installed: false },
        { recordsRoot: records },
      ),
      /cannot safely/,
    );
  } finally {
    f.cleanup();
  }
});
test('uses authentic registry aliases rather than inventing records from display names', async () => {
  const f = fixture();
  try {
    const folder = library(f.root, 'Prism', descriptor),
      records = path.join(f.root, 'records');
    fs.mkdirSync(records);
    const p = {
      ...product,
      title: 'Prism',
      installed: true,
      activationState: 'ACTIVATION_STATE_ACTIVATED',
      components: [{ name: 'COMPONENT_NAME_CONTENTDIR', currentPath: folder }],
    };
    fs.writeFileSync(
      path.join(records, 'Reaktor Prism.json'),
      JSON.stringify({ ContentDir: folder, ContentVersion: '1.6.2' }),
    );
    const result = await saveReceipts(f.root, [p], { recordsRoot: records });
    assert.equal(result[0].state, 'saved');
    const receipt = JSON.parse(
      fs.readFileSync(path.join(vaultRoot(f.root), 'receipts', p.upid + '.json')),
    );
    assert.equal(receipt.recordName, 'Reaktor Prism');
    assert.equal(receipt.record.ContentVersion, '1.6.2');
    assert.equal(fs.existsSync(path.join(records, 'Prism.json')), false);
  } finally {
    f.cleanup();
  }
});

test('rollback preserves a record changed by NI after the receipt was restored', async () => {
  const f = fixture();
  try {
    const folder = library(f.root, 'No Descriptor', null);
    const records = path.join(f.root, 'mock-records');
    fs.mkdirSync(records);
    const p = {
      ...product,
      installed: true,
      activationState: 'ACTIVATION_STATE_ACTIVATED',
      components: [{ name: 'COMPONENT_NAME_CONTENTDIR', currentPath: folder }],
    };
    const dest = recordPath(p.title, records);
    fs.writeFileSync(dest, JSON.stringify({ ContentDir: folder, ContentVersion: '1.0.0' }));
    await saveReceipts(f.root, [p], { recordsRoot: records });
    fs.unlinkSync(dest);
    const restored = await restoreReceipt(
      f.root,
      { upid: p.upid, folder },
      { ...p, installed: false },
      { recordsRoot: records },
    );
    const updated = JSON.stringify({ ContentDir: folder, ContentVersion: '1.1.0' });
    fs.writeFileSync(dest, updated);
    restored.rollback();
    assert.equal(fs.readFileSync(dest, 'utf8'), updated);
  } finally {
    f.cleanup();
  }
});
