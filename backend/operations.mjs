// SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
import { publicProduct } from './native.mjs';
import { assertRootIdentity } from './core.mjs';
import {
  assertNoDuplicateUpdates,
  assertUpdateSelection,
  requestOfficialUpdate,
  updateCandidates,
} from './updates.mjs';

// Re-read mutable daemon state immediately before each submission. The daemon
// provides no transaction spanning this check and another client's submission.
export async function startReviewedUpdate(
  api,
  root,
  expectedRoot,
  row,
  artifacts,
  { cancelled = () => false } = {},
) {
  if (cancelled()) throw Error('CANCELLED');
  const preferences = (await api.call('getPreferencesRequest')).getPreferencesResponse.preferences;
  if (preferences.contentLocation !== root) {
    throw Error('Native Access Content location changed. Check updates again.');
  }
  const products = (await api.call('knownProductsRequest')).knownProductsResponse.knownProducts.map(
    publicProduct,
  );
  const queue =
    (await api.call('activeDeploymentsRequest')).activeDeploymentsResponse.activeDeployments || [];
  assertRootIdentity(root, expectedRoot);
  assertNoDuplicateUpdates([row], queue);
  assertUpdateSelection(
    { rows: [row] },
    [row.id],
    updateCandidates(root, products, artifacts, queue),
  );
  if (cancelled()) throw Error('CANCELLED');
  return requestOfficialUpdate(api, row);
}

// Resume only the exact job that this repair paused. Jobs that were already
// paused by the user, cancelled or advanced to installation are left alone.
export async function resumeRepairDownload(api, deploymentId) {
  const queue =
    (await api.call('activeDeploymentsRequest')).activeDeploymentsResponse.activeDeployments || [];
  if (
    !queue.some((job) => job.deploymentId === deploymentId && job.state === 'STATE_DOWNLOAD_PAUSED')
  ) {
    return false;
  }
  await api.call('resumeDownloadRequest', { deploymentId });
  return true;
}

export function rollbackPendingRestores(restores) {
  const errors = [];
  for (const restore of restores) {
    if (restore.validated) continue;
    try {
      restore.rollback();
    } catch (error) {
      errors.push({
        title: restore.title,
        message: 'Could not remove an unconfirmed restored record: ' + error.message,
      });
    }
  }
  return errors;
}
