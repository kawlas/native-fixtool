// SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { prepareRuntime } from './native-bootstrap.mjs';
export const READ_REQUESTS = new Set([
  'daemonVersionRequest',
  'knownProductsRequest',
  'activeDeploymentsRequest',
  'getPreferencesRequest',
  'auth0AccessTokenRequest',
]);
const WRITE_REQUESTS = new Set([
  'locateLibraryRequest',
  'refreshProductListRequest',
  'setPreferencesRequest',
  'pauseDownloadRequest',
  'cancelDownloadRequest',
  'startDeploymentsRequest',
  'resumeDownloadRequest',
]);
export function assertSupportedDaemon(daemon) {
  if (daemon?.major !== 1 || daemon?.minor !== 32 || daemon?.build !== ' (R0)')
    throw Error(
      'Unsupported NTKDaemon adapter version. This release was verified with NTKDaemon 1.32 (R0).',
    );
}
export function validateNativeRequest(writable, key, arg = {}) {
  if (!READ_REQUESTS.has(key) && !(writable && WRITE_REQUESTS.has(key)))
    throw Error('Operation not permitted: ' + key);
  if (
    key === 'startDeploymentsRequest' &&
    (!Array.isArray(arg.deployments) ||
      !arg.deployments.length ||
      arg.deployments.some((d) => !d.upid || d.type !== 'DEPLOYMENT_TYPE_UPDATE'))
  )
    throw Error('Only explicit existing-product updates are permitted');
}
export async function connectNative({ writable = false } = {}) {
  const adapter = prepareRuntime();
  const require = createRequire(path.join(adapter.runtime, 'codec.cjs'));
  const codec = require('./codec.cjs');
  const { NtkZeromqClient } = await import(
    pathToFileURL(
      path.join(
        adapter.runtime,
        'node_modules/@native-instruments/access-ntk-zeromq-node/dist/client.mjs',
      ),
    )
  );
  const client = new NtkZeromqClient();
  return {
    adapter,
    async call(key, arg = {}) {
      validateNativeRequest(writable, key, arg);
      const bytes = codec
        .encode(
          codec.fromJSON({ header: { version: { major: 8, minor: 1, micro: 4 } }, [key]: arg }),
        )
        .finish();
      const result = codec.toJSON(
        codec.decode(await client.send(bytes, READ_REQUESTS.has(key) ? 10000 : 60000)),
      );
      if (result.errorResponse)
        throw Error(result.errorResponse.message || JSON.stringify(result.errorResponse));
      return result;
    },
    async close() {
      await client.dispose(100);
    },
  };
}
export function publicProduct(p) {
  return {
    upid: p.upid,
    title: p.title,
    type: p.type,
    installed: !!p.installed,
    isBroken: !!p.isBroken,
    isOwned: !!p.isOwned,
    updateable: !!p.updateable,
    targetSize: p.targetSize || null,
    installedVersion: p.installedVersion || {},
    targetVersion: p.targetVersion || {},
    activationState: p.activationState || '',
    components: p.components || [],
    licenses: p.licenses || [],
    installedSize: p.installedSize || '0',
  };
}
export function version(v) {
  return ['major', 'minor', 'micro'].map((k) => v?.[k] || 0).join('.');
}
