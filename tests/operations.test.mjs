// SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  startReviewedUpdate,
  resumeRepairDownload,
  rollbackPendingRestores,
} from '../backend/operations.mjs';
import { rootIdentity } from '../backend/core.mjs';
import { updateCandidates } from '../backend/updates.mjs';
import { assertSupportedDaemon } from '../backend/native.mjs';

function fixture() {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'ni-fix-review-')));
  const folder = path.join(root, 'Test Library');
  fs.mkdirSync(folder);
  const product = {
    upid: 'p1',
    title: 'Test',
    type: 'PRODUCT_TYPE_CONTENT',
    installed: true,
    isOwned: true,
    installedVersion: { major: 1 },
    targetVersion: { major: 2 },
    components: [{ name: 'COMPONENT_NAME_CONTENTDIR', currentPath: folder }],
  };
  const artifacts = [
    {
      upid: 'p1',
      type: 'content',
      file_type: 'path',
      platform: 'all',
      version: '2.0.0+1',
      update_id: 'a1',
    },
  ];
  const row = updateCandidates(root, [product], artifacts)[0];
  const calls = [];
  const state = { products: [product], queue: [], location: root };
  const api = {
    async call(key, arg) {
      calls.push({ key, arg });
      if (key === 'getPreferencesRequest')
        return { getPreferencesResponse: { preferences: { contentLocation: state.location } } };
      if (key === 'knownProductsRequest')
        return { knownProductsResponse: { knownProducts: state.products } };
      if (key === 'activeDeploymentsRequest')
        return { activeDeploymentsResponse: { activeDeployments: state.queue } };
      if (key === 'startDeploymentsRequest')
        return { startDeploymentsResponse: { results: [{ upid: 'p1', deploymentId: 'new-job' }] } };
      if (key === 'resumeDownloadRequest') return {};
      throw Error('Unexpected request: ' + key);
    },
  };
  return {
    root,
    folder,
    row,
    artifacts,
    state,
    calls,
    api,
    cleanup: () => fs.rmSync(root, { recursive: true, force: true }),
  };
}

test('submission rechecks current NI state and preserves unrelated downloads', async () => {
  const f = fixture();
  try {
    f.state.queue = [{ upid: 'other', deploymentId: 'existing', state: 'STATE_DOWNLOADING' }];
    assert.equal(
      await startReviewedUpdate(f.api, f.root, rootIdentity(f.root), f.row, f.artifacts),
      'new-job',
    );
    assert.equal(f.calls.at(-1).key, 'startDeploymentsRequest');
    assert.deepEqual(f.calls.at(-1).arg.deployments, [
      { upid: 'p1', type: 'DEPLOYMENT_TYPE_UPDATE' },
    ]);
    assert.equal(f.state.queue[0].state, 'STATE_DOWNLOADING');
  } finally {
    f.cleanup();
  }
});

test('a job added after the earlier plan blocks the submission', async () => {
  const f = fixture();
  try {
    f.state.queue = [{ upid: 'p1', deploymentId: 'added-in-native-access' }];
    await assert.rejects(
      startReviewedUpdate(f.api, f.root, rootIdentity(f.root), f.row, f.artifacts),
      /already/,
    );
    assert.ok(f.calls.every((c) => c.key !== 'startDeploymentsRequest'));
  } finally {
    f.cleanup();
  }
});

test('changed preferences, ownership and folder identity block submission', async () => {
  const f = fixture();
  try {
    const identity = rootIdentity(f.root);
    f.state.location = '/other';
    await assert.rejects(
      startReviewedUpdate(f.api, f.root, identity, f.row, f.artifacts),
      /location changed/,
    );
    f.state.location = f.root;
    f.state.products = [{ ...f.state.products[0], isOwned: false }];
    await assert.rejects(
      startReviewedUpdate(f.api, f.root, identity, f.row, f.artifacts),
      /state changed/,
    );
    f.state.products[0].isOwned = true;
    fs.rmdirSync(f.folder);
    fs.symlinkSync(os.tmpdir(), f.folder);
    await assert.rejects(
      startReviewedUpdate(f.api, f.root, identity, f.row, f.artifacts),
      /state changed/,
    );
    assert.ok(f.calls.every((c) => c.key !== 'startDeploymentsRequest'));
  } finally {
    f.cleanup();
  }
});

test('cancellation during revalidation does not launch an update', async () => {
  const f = fixture();
  try {
    await assert.rejects(
      startReviewedUpdate(f.api, f.root, rootIdentity(f.root), f.row, f.artifacts, {
        cancelled: () => f.calls.some((c) => c.key === 'activeDeploymentsRequest'),
      }),
      /CANCELLED/,
    );
    assert.ok(f.calls.every((c) => c.key !== 'startDeploymentsRequest'));
  } finally {
    f.cleanup();
  }
});

test('repair resumes only the exact download it paused', async () => {
  const f = fixture();
  try {
    f.state.queue = [
      { deploymentId: 'repair-paused', state: 'STATE_DOWNLOAD_PAUSED' },
      { deploymentId: 'user-paused', state: 'STATE_DOWNLOAD_PAUSED' },
    ];
    assert.equal(await resumeRepairDownload(f.api, 'repair-paused'), true);
    assert.deepEqual(
      f.calls.filter((c) => c.key === 'resumeDownloadRequest'),
      [{ key: 'resumeDownloadRequest', arg: { deploymentId: 'repair-paused' } }],
    );
  } finally {
    f.cleanup();
  }
});

test('repair cleanup leaves cancelled, installing and absent jobs alone', async () => {
  const f = fixture();
  try {
    for (const queue of [
      [],
      [{ deploymentId: 'own', state: 'STATE_INSTALLING' }],
      [{ deploymentId: 'other', state: 'STATE_DOWNLOAD_PAUSED' }],
    ]) {
      f.state.queue = queue;
      assert.equal(await resumeRepairDownload(f.api, 'own'), false);
    }
    assert.ok(f.calls.every((c) => c.key !== 'resumeDownloadRequest'));
  } finally {
    f.cleanup();
  }
});

test('unsupported or incomplete daemon versions fail the adapter gate', () => {
  assert.doesNotThrow(() => assertSupportedDaemon({ major: 1, minor: 32, build: ' (R0)' }));
  for (const daemon of [
    undefined,
    {},
    { major: 1, minor: 33, build: ' (R0)' },
    { major: 1, minor: 32, build: ' (R1)' },
  ]) {
    assert.throws(() => assertSupportedDaemon(daemon), /Unsupported NTKDaemon/);
  }
});

test('rollback reports a failed removal, continues other records and preserves validated records', () => {
  const visited = [];
  const errors = rollbackPendingRestores([
    {
      title: 'confirmed',
      validated: true,
      rollback() {
        visited.push('confirmed');
      },
    },
    {
      title: 'blocked',
      rollback() {
        visited.push('blocked');
        throw Error('read-only record');
      },
    },
    {
      title: 'pending',
      rollback() {
        visited.push('pending');
      },
    },
  ]);
  assert.deepEqual(visited, ['blocked', 'pending']);
  assert.equal(errors.length, 1);
  assert.equal(errors[0].title, 'blocked');
  assert.match(errors[0].message, /read-only record/);
});
