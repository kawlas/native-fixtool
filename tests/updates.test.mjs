// SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {
  contentManifest,
  auditUpdate,
  updateCandidates,
  updatePlan,
  assertUpdateSelection,
  isNewer,
} from '../backend/updates.mjs';
const hash = (data, algo = 'sha256') => crypto.createHash(algo).update(data).digest('hex');
function fixture() {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'lb-update-'))),
    folder = path.join(root, 'Test Library');
  fs.mkdirSync(folder);
  return { root, folder, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}
function manifest(data, { name = 'Test Library/test.nkx', pieceSize = 4, override = [] } = {}) {
  const chunks = [];
  for (let i = 0; i < data.length; i += pieceSize)
    chunks.push(hash(data.subarray(i, i + pieceSize), 'sha1'));
  return `<metalink xmlns="urn:ietf:params:xml:ns:metalink"><file name="${name}"><size>${data.length}</size><hash type="sha-256">${hash(data)}</hash><pieces type="sha-1" length="${pieceSize}">${chunks.map((h, i) => '<hash>' + (override[i] || h) + '</hash>').join('')}</pieces></file></metalink>`;
}
const product = {
  upid: 'p1',
  title: 'Test',
  type: 'PRODUCT_TYPE_CONTENT',
  installed: true,
  isOwned: true,
  installedVersion: { major: 1 },
  targetVersion: { major: 2 },
};
const artifact = {
  upid: 'p1',
  type: 'content',
  file_type: 'path',
  platform: 'all',
  version: '2.0.0+1',
  update_id: 'a1',
  filesize: 12,
};
test('version comparison is numeric and does not interpret file sizes as update size', () => {
  assert.equal(isNewer('1.10.0', '1.9.0'), true);
  assert.equal(isNewer('1.0.0', '1.0.0'), false);
  assert.equal(isNewer('bad', '1.0.0'), false);
});
test('manifest strips exactly one expected library root, rejects traversal, duplicate and wrong roots', () => {
  const f = fixture();
  try {
    const xml = manifest(Buffer.from('abcdefgh'));
    assert.equal(contentManifest(xml, f.folder)[0].name, 'test.nkx');
    assert.throws(
      () => contentManifest(manifest(Buffer.from('a'), { name: 'Other Library/a' }), f.folder),
      /differs/,
    );
    assert.throws(
      () =>
        contentManifest(manifest(Buffer.from('a'), { name: 'Test Library/../escape' }), f.folder),
      /Unsafe/,
    );
    const file = xml.match(/<file.*<\/file>/s)[0];
    assert.throws(
      () => contentManifest(xml.replace('</metalink>', file + '</metalink>'), f.folder),
      /Duplicate/,
    );
  } finally {
    f.cleanup();
  }
});
test('changed file retains exact matching pieces and reports a transfer estimate rather than full size', async () => {
  const f = fixture();
  try {
    const data = Buffer.from('abcdefghijkl');
    fs.writeFileSync(path.join(f.folder, 'test.nkx'), 'abcdXXXXijkl');
    const r = await auditUpdate(f.folder, contentManifest(manifest(data), f.folder));
    assert.equal(r.matchingFiles, 0);
    assert.equal(r.changedFileBytes, 12);
    assert.equal(r.matchingPieceBytes, 8);
    assert.equal(r.estimatedTransferBytes, 4);
    assert.equal(fs.readFileSync(path.join(f.folder, 'test.nkx'), 'utf8'), 'abcdXXXXijkl');
  } finally {
    f.cleanup();
  }
});
test('latest bytes with an older installation record produce zero estimated payload, without altering the version', async () => {
  const f = fixture();
  try {
    fs.writeFileSync(path.join(f.folder, 'test.nkx'), 'abcdefghijkl');
    const r = await auditUpdate(
      f.folder,
      contentManifest(manifest(Buffer.from('abcdefghijkl')), f.folder),
    );
    assert.equal(r.matchingFiles, 1);
    assert.equal(r.estimatedTransferBytes, 0);
    assert.equal(product.installedVersion.major, 1);
  } finally {
    f.cleanup();
  }
});
test('missing files are full transfer; symlinks, inconsistent hashes and cancellation fail honestly', async () => {
  const f = fixture();
  try {
    const data = Buffer.from('abcdefghijkl'),
      files = contentManifest(manifest(data), f.folder);
    assert.equal((await auditUpdate(f.folder, files)).estimatedTransferBytes, 12);
    fs.symlinkSync('/etc/hosts', path.join(f.folder, 'test.nkx'));
    await assert.rejects(auditUpdate(f.folder, files), /Symlink/);
    fs.unlinkSync(path.join(f.folder, 'test.nkx'));
    fs.writeFileSync(path.join(f.folder, 'test.nkx'), data);
    await assert.rejects(
      auditUpdate(
        f.folder,
        contentManifest(manifest(data, { override: ['0'.repeat(40)] }), f.folder),
      ),
      /Inconsistent/,
    );
    await assert.rejects(auditUpdate(f.folder, files, { cancelled: () => true }), /CANCELLED/);
  } finally {
    f.cleanup();
  }
});
test('updates require ownership, exact target, valid registered folder and unchanged reviewed identity', () => {
  const f = fixture();
  try {
    const p = {
      ...product,
      components: [{ name: 'COMPONENT_NAME_CONTENTDIR', currentPath: f.folder }],
    };
    const rows = updateCandidates(f.root, [p], [artifact]);
    assert.equal(rows[0].state, 'ready');
    assert.equal(
      updateCandidates(f.root, [{ ...p, isOwned: false }], [artifact])[0].state,
      'blocked',
    );
    assert.equal(
      updateCandidates(f.root, [p], [{ ...artifact, version: '1.9.0' }])[0].state,
      'nativeOnly',
    );
    const plan = updatePlan(f.root, rows, '3.26.0');
    assert.equal(assertUpdateSelection(plan, ['p1'], rows).length, 1);
    assert.throws(
      () => assertUpdateSelection(plan, ['p1'], [{ ...rows[0], targetVersion: '3.0.0' }]),
      /changed/,
    );
    assert.throws(() => assertUpdateSelection(plan, ['p1', 'p1'], rows), /Select/);
  } finally {
    f.cleanup();
  }
});
test('official update request uses UPDATE only; keeps unrelated queue jobs and rejects duplicates or daemon rejection', async () => {
  const { assertNoDuplicateUpdates, requestOfficialUpdate } =
    await import('../backend/updates.mjs');
  const row = { upid: 'selected' };
  const queue = [{ upid: 'other', state: 'STATE_DOWNLOADING' }];
  assert.doesNotThrow(() => assertNoDuplicateUpdates([row], queue));
  assert.equal(queue[0].state, 'STATE_DOWNLOADING');
  assert.throws(() => assertNoDuplicateUpdates([row], [{ upid: 'selected' }]), /already/);
  const calls = [];
  const api = {
    call: async (k, v) => {
      calls.push({ k, v });
      return { startDeploymentsResponse: { results: [{ upid: 'selected', deploymentId: 'd1' }] } };
    },
  };
  assert.equal(await requestOfficialUpdate(api, row), 'd1');
  assert.deepEqual(calls, [
    {
      k: 'startDeploymentsRequest',
      v: { deployments: [{ upid: 'selected', type: 'DEPLOYMENT_TYPE_UPDATE' }] },
    },
  ]);
  await assert.rejects(
    requestOfficialUpdate(
      {
        call: async () => ({
          startDeploymentsResponse: { results: [{ upid: 'other', deploymentId: 'wrong' }] },
        }),
      },
      row,
    ),
    /not accept/,
  );
});
test('native adapter refuses full reinstall, uninstall and updates from a read-only client', async () => {
  const { validateNativeRequest } = await import('../backend/native.mjs');
  assert.throws(
    () =>
      validateNativeRequest(false, 'startDeploymentsRequest', {
        deployments: [{ upid: 'p', type: 'DEPLOYMENT_TYPE_UPDATE' }],
      }),
    /not permitted/,
  );
  assert.throws(
    () =>
      validateNativeRequest(true, 'startDeploymentsRequest', {
        deployments: [{ upid: 'p', type: 'DEPLOYMENT_TYPE_FULL' }],
      }),
    /Only explicit/,
  );
  assert.throws(() => validateNativeRequest(true, 'uninstallRequest', {}), /not permitted/);
  assert.doesNotThrow(() =>
    validateNativeRequest(true, 'startDeploymentsRequest', {
      deployments: [{ upid: 'p', type: 'DEPLOYMENT_TYPE_UPDATE' }],
    }),
  );
});
test('a shared version number is insufficient when multiple artifacts claim it', () => {
  const f = fixture();
  try {
    const p = {
      ...product,
      components: [{ name: 'COMPONENT_NAME_CONTENTDIR', currentPath: f.folder }],
    };
    assert.equal(
      updateCandidates(
        f.root,
        [p],
        [artifact, { ...artifact, update_id: 'other', version: '2.0.0+2' }],
      )[0].state,
      'nativeOnly',
    );
  } finally {
    f.cleanup();
  }
});
test('session completion requires NI target version at the exact location and no active deployment', async () => {
  const { sessionStatus } = await import('../backend/updates.mjs');
  const session = {
    deployments: [
      {
        upid: 'p1',
        title: 'Test',
        folder: '/drive/Test Library',
        targetVersion: '2.0.0',
        deploymentId: 'own',
      },
    ],
  };
  const p = {
    ...product,
    installedVersion: { major: 2 },
    components: [{ name: 'COMPONENT_NAME_CONTENTDIR', currentPath: '/drive/Test Library' }],
  };
  assert.equal(sessionStatus(session, [p], [])[0].state, 'confirmed');
  assert.equal(
    sessionStatus(
      session,
      [{ ...p, components: [{ name: 'COMPONENT_NAME_CONTENTDIR', currentPath: '/other/path' }] }],
      [],
    )[0].state,
    'notConfirmed',
  );
  assert.equal(
    sessionStatus(session, [p], [{ deploymentId: 'own', state: 'STATE_DOWNLOADING' }])[0].state,
    'STATE_DOWNLOADING',
  );
});

test('piece reuse remains correct across stream boundaries and truncated files', async () => {
  const f = fixture();
  try {
    const target = Buffer.alloc(4 * 1024 * 1024 + 31);
    for (let i = 0; i < target.length; i++) target[i] = (i * 31 + (i >>> 8)) % 251;
    const pieceSize = 4093;
    const files = contentManifest(manifest(target, { pieceSize }), f.folder);
    const changed = Buffer.from(target);
    changed[4 * 1024 * 1024 - 1] ^= 255;
    changed[4 * 1024 * 1024 + 1] ^= 255;
    for (const local of [target, changed, target.subarray(0, target.length - 17)]) {
      fs.writeFileSync(path.join(f.folder, 'test.nkx'), local);
      let expected = 0;
      for (let start = 0; start < target.length; start += pieceSize) {
        const wanted = target.subarray(start, Math.min(target.length, start + pieceSize));
        if (local.subarray(start, start + wanted.length).equals(wanted)) expected += wanted.length;
      }
      const result = await auditUpdate(f.folder, files);
      assert.equal(result.matchingPieceBytes, expected);
      assert.equal(result.estimatedTransferBytes, target.length - expected);
      assert.deepEqual(fs.readFileSync(path.join(f.folder, 'test.nkx')), local);
    }
  } finally {
    f.cleanup();
  }
});
