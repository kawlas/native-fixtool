// SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { connectNative, publicProduct, version, assertSupportedDaemon } from './native.mjs';
import {
  canonicalRoot,
  rootIdentity,
  assertRootIdentity,
  inventory,
  makePlan,
  atomicJSON,
  vaultRoot,
  acquireLock,
  parseMetalink,
  verifyFiles,
  hashBytes,
} from './core.mjs';
import { updateCloud } from './cloud.mjs';
import {
  updateCandidates,
  contentManifest,
  auditUpdate,
  updatePlan,
  assertUpdateSelection,
  publicUpdates,
  assertNoDuplicateUpdates,
  sessionStatus,
} from './updates.mjs';
import { backupRecords, saveReceipts, restoreReceipt } from './vault.mjs';
import {
  startReviewedUpdate,
  resumeRepairDownload,
  rollbackPendingRestores,
} from './operations.mjs';
const args = process.argv.slice(2),
  command = args[0] || 'scan';
const option = (k) => {
  const i = args.indexOf('--' + k);
  return i < 0 ? undefined : args[i + 1];
};
let cancelled = false;
process.on('SIGINT', () => {
  cancelled = true;
  emit({ type: 'progress', stage: 'cancelling' });
});
process.on('SIGTERM', () => {
  cancelled = true;
});
function emit(v) {
  process.stdout.write(JSON.stringify(v) + '\n');
}
const progress = (p) => emit({ type: 'progress', ...p });
const installedAt = (p, folder) =>
  p?.installed &&
  !p.isBroken &&
  p.components?.some((c) => c.name === 'COMPONENT_NAME_CONTENTDIR' && c.currentPath === folder);
let api, releaseLock, repairPausedID;
const activeRestores = [];
const localReports = path.join(os.homedir(), 'Library/Application Support/Library Bridge/reports');
const operationID =
  new Date().toISOString().replaceAll(':', '-') + '-' + crypto.randomUUID().slice(0, 6);
const report = {
  schema: 1,
  id: operationID,
  date: new Date().toISOString(),
  command,
  actions: [],
  errors: [],
};
function saveReport() {
  fs.mkdirSync(localReports, { recursive: true });
  const dest = path.join(localReports, operationID + '.json');
  atomicJSON(dest, report);
  return dest;
}
async function finishRepairPause() {
  if (!repairPausedID || !api) return;
  const deploymentId = repairPausedID;
  repairPausedID = undefined;
  try {
    if (await resumeRepairDownload(api, deploymentId))
      report.actions.push({ operation: 'resumeDownloadPausedByRepair', deploymentId });
  } catch (e) {
    report.errors.push({
      message:
        'Could not resume the download paused by this repair. Resume it in Native Access. ' +
        e.message,
    });
  }
}
async function getProducts() {
  return (await api.call('knownProductsRequest')).knownProductsResponse.knownProducts.map(
    publicProduct,
  );
}
async function openNative(writable = false) {
  try {
    api = await connectNative({ writable });
    const daemon = (await api.call('daemonVersionRequest')).daemonVersionResponse;
    assertSupportedDaemon(daemon);
    return {
      connected: true,
      version: api.adapter.version,
      daemon: JSON.stringify(daemon),
      message: 'Connected to Native Access',
      supportsRepair: true,
    };
  } catch (e) {
    if (api) {
      await api.close();
      api = null;
    }
    return {
      connected: false,
      version: '',
      daemon: '',
      message: String(e.message || e),
      supportsRepair: false,
    };
  }
}
function summary(rows) {
  return {
    total: rows.length,
    registered: rows.filter((r) => r.state === 'registered').length,
    recoverable: rows.filter((r) => ['canLocate', 'receiptAvailable'].includes(r.state)).length,
    review: rows.filter((r) => !['registered', 'canLocate', 'receiptAvailable'].includes(r.state))
      .length,
  };
}
function readableDownloads(deployments) {
  return deployments.map((d) => {
    let verified = 0,
      httpGetRequests = 0;
    const file = path.join(
      '/Users/Shared/Native Instruments/Logs/NTK/DownloadLogs',
      d.deploymentId + '.log',
    );
    try {
      const stat = fs.statSync(file),
        fd = fs.openSync(file, 'r');
      try {
        const length = Math.min(stat.size, 20 * 1024 * 1024),
          buf = Buffer.alloc(length);
        fs.readSync(fd, buf, 0, length, stat.size - length);
        const s = buf.toString();
        verified = (s.match(/Verification finished successfully/g) || []).length;
        httpGetRequests = (s.match(/^GET /gm) || []).length;
      } finally {
        fs.closeSync(fd);
      }
    } catch {
      // NI may rotate or omit optional diagnostic logs; this is not completion evidence.
    }
    return {
      title: d.title,
      state: d.state,
      progress: d.progress || 0,
      verifiedFilesObserved: verified,
      httpGetRequestsObserved: httpGetRequests,
    };
  });
}
try {
  if (command === 'discover') {
    const connection = await openNative();
    let suggestedLibraryPath = '';
    if (api) {
      const prefs = (await api.call('getPreferencesRequest')).getPreferencesResponse.preferences;
      suggestedLibraryPath = prefs.contentLocation || '';
    }
    emit({ type: 'result', command, connection, suggestedLibraryPath });
  } else {
    const root = canonicalRoot(option('library') || '');
    report.root = root;
    progress({ stage: 'connect' });
    const connection =
      command === 'verify'
        ? {
            connected: false,
            version: '',
            supportsRepair: false,
            message: 'Offline SHA-256 verification',
          }
        : await openNative(
            ['repair', 'update-start', 'update-pause', 'update-resume'].includes(command),
          );
    let products = connection.connected ? await getProducts() : [];
    progress({ stage: 'scan' });
    let rows =
      command === 'verify' || command.startsWith('update')
        ? []
        : inventory(root, products, { connected: connection.connected });
    if (
      [
        'updates',
        'update-audit',
        'update-start',
        'update-status',
        'update-pause',
        'update-resume',
      ].includes(command)
    ) {
      if (!connection.connected) throw Error(connection.message);
      if (
        command === 'update-status' ||
        command === 'update-pause' ||
        command === 'update-resume'
      ) {
        const sessionFile = option('session');
        if (!sessionFile) throw Error('An update session is required');
        const session = JSON.parse(fs.readFileSync(sessionFile));
        if (session.kind !== 'updateSession' || session.nativeVersion !== connection.version)
          throw Error('Invalid update session');
        assertRootIdentity(root, session.root);
        let queue =
          (await api.call('activeDeploymentsRequest')).activeDeploymentsResponse
            .activeDeployments || [];
        if (command === 'update-pause')
          for (const d of queue.filter(
            (d) =>
              session.deployments.some((x) => x.deploymentId === d.deploymentId) &&
              d.state === 'STATE_DOWNLOADING',
          )) {
            await api.call('pauseDownloadRequest', { deploymentId: d.deploymentId });
            report.actions.push({ operation: 'pauseOwnUpdate', title: d.title });
          }
        if (command === 'update-resume')
          for (const d of queue.filter(
            (d) =>
              session.deployments.some((x) => x.deploymentId === d.deploymentId) &&
              d.state === 'STATE_DOWNLOAD_PAUSED',
          )) {
            await api.call('resumeDownloadRequest', { deploymentId: d.deploymentId });
            report.actions.push({ operation: 'resumeOwnUpdate', title: d.title });
          }
        products = await getProducts();
        queue =
          (await api.call('activeDeploymentsRequest')).activeDeploymentsResponse
            .activeDeployments || [];
        const statuses = sessionStatus(session, products, queue);
        emit({
          type: 'result',
          command,
          root,
          connection,
          updateSessionFile: sessionFile,
          updateStatuses: statuses,
          downloads: readableDownloads(
            queue.filter((d) => session.deployments.some((x) => x.deploymentId === d.deploymentId)),
          ),
          reportPath: command !== 'update-status' ? saveReport() : undefined,
        });
      } else {
        progress({ stage: 'updateCatalog' });
        const cloud = await updateCloud(api, { cancelled: () => cancelled });
        const catalog = await cloud.catalog();
        const currentQueue =
          (await api.call('activeDeploymentsRequest')).activeDeploymentsResponse
            .activeDeployments || [];
        let updates = updateCandidates(root, products, catalog, currentQueue);
        let chosen = [];
        if (command !== 'updates') {
          const previous = JSON.parse(fs.readFileSync(option('plan') || ''));
          if (previous.kind !== 'updates' || previous.nativeVersion !== connection.version)
            throw Error('Check updates again with this version of Native Access');
          assertRootIdentity(root, previous.root);
          chosen = assertUpdateSelection(previous, JSON.parse(option('selected') || '[]'), updates);
        }
        if (command === 'update-audit') {
          for (const row of chosen) {
            if (cancelled) throw Error('CANCELLED');
            progress({ stage: 'updateManifest', title: row.title });
            const xml = await cloud.manifest(row._artifact);
            const files = contentManifest(xml, row.folder);
            row.manifestSha256 = hashBytes(xml);
            let last = 0;
            row.audit = await auditUpdate(row.folder, files, {
              cancelled: () => cancelled,
              progress: (p) => {
                const now = Date.now();
                if (now - last > 200) {
                  progress(p);
                  last = now;
                }
              },
            });
            report.actions.push({
              operation: 'auditUpdate',
              title: row.title,
              manifestSha256: row.manifestSha256,
              audit: row.audit,
            });
            updates = updates.map((r) => (r.id === row.id ? row : r));
            saveReport();
          }
        }
        if (command === 'update-start') {
          releaseLock = acquireLock(root);
          const queue =
            (await api.call('activeDeploymentsRequest')).activeDeploymentsResponse
              .activeDeployments || [];
          assertNoDuplicateUpdates(chosen, queue);
          const prefs = (await api.call('getPreferencesRequest')).getPreferencesResponse
            .preferences;
          if (prefs.contentLocation !== root)
            throw Error(
              'Set Native Access Content location to this library parent folder before updating: ' +
                root,
            );
          // Fetch only manifests first. Never start one update before all selected paths pass.
          for (const row of chosen) {
            if (cancelled) throw Error('CANCELLED');
            progress({ stage: 'updateManifest', title: row.title });
            contentManifest(await cloud.manifest(row._artifact), row.folder);
          }
          products = await getProducts();
          assertUpdateSelection(
            updatePlan(root, chosen, connection.version),
            chosen.map((r) => r.id),
            updateCandidates(root, products, catalog),
          );
          report.backup = backupRecords(
            root,
            products.filter((p) => chosen.some((r) => r.upid === p.upid)),
            { label: 'before-updates' },
          );
          saveReport();
          const session = {
            schema: 1,
            kind: 'updateSession',
            date: new Date().toISOString(),
            root: rootIdentity(root),
            nativeVersion: connection.version,
            deployments: [],
          };
          const sessionsDir = path.join(
            os.homedir(),
            'Library/Application Support/Library Bridge/update-sessions',
          );
          const sessionFile = path.join(sessionsDir, operationID + '.json');
          atomicJSON(sessionFile, session);
          for (const row of chosen) {
            if (cancelled) break;
            assertRootIdentity(root, session.root);
            progress({ stage: 'startUpdate', title: row.title });
            let deploymentId;
            try {
              deploymentId = await startReviewedUpdate(api, root, session.root, row, catalog, {
                cancelled: () => cancelled,
              });
            } catch (e) {
              if (e.message === 'CANCELLED') cancelled = true;
              else report.errors.push({ title: row.title, message: e.message });
              saveReport();
              break;
            }
            session.deployments.push({
              upid: row.upid,
              title: row.title,
              folder: row.folder,
              targetVersion: row.targetVersion,
              deploymentId,
            });
            atomicJSON(sessionFile, session);
            report.actions.push({
              operation: 'startOfficialUpdate',
              title: row.title,
              deploymentId,
            });
            saveReport();
          }
          report.cancelled = cancelled;
          emit({
            type: 'result',
            command,
            root,
            connection,
            updateSessionFile: session.deployments.length ? sessionFile : undefined,
            started: session.deployments.length,
            cancelled,
            reportPath: saveReport(),
            errors: report.errors,
          });
        } else {
          const plan = updatePlan(root, updates, connection.version),
            planFile = path.join(
              os.homedir(),
              'Library/Application Support/Library Bridge/update-plans',
              hashBytes(JSON.stringify(plan)) + '.json',
            );
          atomicJSON(planFile, plan);
          report.updates = publicUpdates(updates);
          const reportPath = saveReport();
          emit({
            type: 'result',
            command,
            root,
            connection,
            updates: publicUpdates(updates),
            updatePlanFile: planFile,
            reportPath,
            downloads: readableDownloads(currentQueue),
          });
        }
      }
    } else if (command === 'scan') {
      let downloads = [];
      if (api)
        try {
          downloads = readableDownloads(
            (await api.call('activeDeploymentsRequest')).activeDeploymentsResponse
              .activeDeployments || [],
          );
        } catch {
          // Optional queue diagnostics must not prevent a read-only library inventory.
        }
      const plan = makePlan(root, rows, connection);
      const planID = hashBytes(JSON.stringify(plan));
      const planDir = path.join(os.homedir(), 'Library/Application Support/Library Bridge/plans');
      const planFile = path.join(planDir, planID + '.json');
      atomicJSON(planFile, plan);
      const result = {
        type: 'result',
        command,
        root,
        connection,
        rows,
        summary: summary(rows),
        planFile,
        planID,
        downloads,
        vault: path.join(root, '.library-bridge'),
      };
      emit(result);
    } else if (command === 'repair') {
      if (!connection.supportsRepair) throw Error(connection.message);
      const planFile = option('plan');
      if (!planFile) throw Error('A reviewed scan plan is required');
      const plan = JSON.parse(fs.readFileSync(planFile));
      if (plan.schema !== 1 || plan.nativeVersion !== connection.version)
        throw Error('Native Access compatibility changed. Scan again.');
      assertRootIdentity(root, plan.root);
      const requested = JSON.parse(option('selected') || '[]');
      if (!Array.isArray(requested) || !requested.length)
        throw Error('Select at least one recoverable library');
      const chosen = plan.rows.filter((r) => requested.includes(r.id));
      if (chosen.length !== new Set(requested).size)
        throw Error('Selection does not match the reviewed plan');
      for (const p of chosen) {
        const fresh = rows.find((r) => r.id === p.id);
        if (
          !fresh ||
          fresh.upid !== p.upid ||
          fresh.state !== p.state ||
          fresh.descriptorHash !== p.descriptorHash ||
          fresh.folder !== p.folder
        )
          throw Error('Library state changed: ' + p.title + '. Scan again.');
      }
      releaseLock = acquireLock(root);
      report.plan = { nativeVersion: plan.nativeVersion, root: plan.root, rows: chosen };
      report.backup = backupRecords(
        root,
        products.filter((p) => chosen.some((r) => r.upid === p.upid)),
      );
      saveReport();
      const before =
        (await api.call('activeDeploymentsRequest')).activeDeploymentsResponse.activeDeployments ||
        [];
      report.queueBefore = before.map((d) => ({
        title: d.title,
        upid: d.upid,
        deploymentId: d.deploymentId,
        state: d.state,
      }));
      const active = before.find((d) => d.state === 'STATE_DOWNLOADING');
      if (active) {
        await api.call('pauseDownloadRequest', { deploymentId: active.deploymentId });
        repairPausedID = active.deploymentId;
        report.actions.push({ operation: 'pauseDownloads', title: active.title });
        saveReport();
      }
      const prefs = (await api.call('getPreferencesRequest')).getPreferencesResponse.preferences;
      report.previousPreferences = prefs;
      if (option('set-content') === 'true' && prefs.contentLocation !== root) {
        await api.call('setPreferencesRequest', {
          preferences: { ...prefs, contentLocation: root },
        });
        report.actions.push({
          operation: 'setContentLocation',
          from: prefs.contentLocation,
          to: root,
        });
        saveReport();
      }
      for (const [index, row] of chosen.entries()) {
        if (cancelled) break;
        assertRootIdentity(root, plan.root);
        progress({ stage: 'repair', title: row.title, current: index + 1, total: chosen.length });
        try {
          if (row.state === 'receiptAvailable') {
            const product = products.find((p) => p.upid === row.upid);
            const restore = await restoreReceipt(root, row, product, {
              cancelled: () => cancelled,
              progress,
              validateRoot: () => assertRootIdentity(root, plan.root),
            });
            activeRestores.push({
              ...restore,
              upid: row.upid,
              title: row.title,
              folder: row.folder,
            });
            report.actions.push({
              operation: 'restoreOriginalReceipt',
              title: row.title,
              upid: row.upid,
              evidence: restore.evidence,
            });
          } else {
            const r = (await api.call('locateLibraryRequest', { path: row.folder, upid: row.upid }))
              .locateLibraryResponse;
            if (r?.result !== 'RESULT_SUCCESS')
              throw Error(r?.result || 'Native Access rejected the location');
            report.actions.push({
              operation: 'locate',
              title: row.title,
              upid: row.upid,
              path: row.folder,
            });
          }
        } catch (e) {
          if (e.message === 'CANCELLED') {
            cancelled = true;
            break;
          }
          report.errors.push({ title: row.title, message: e.message });
        }
        saveReport();
      }
      await api.call('refreshProductListRequest');
      const succeeded = new Set(
        report.actions
          .filter((a) => ['locate', 'restoreOriginalReceipt'].includes(a.operation))
          .map((a) => a.upid),
      );
      progress({ stage: 'refresh' });
      for (let n = 0; n < 90; n++) {
        if (cancelled && !activeRestores.length) break;
        products = await getProducts();
        if (
          [...succeeded].every((id) =>
            products.some(
              (p) => p.upid === id && installedAt(p, chosen.find((r) => r.upid === id)?.folder),
            ),
          )
        )
          break;
        await new Promise((r) => setTimeout(r, 2000));
      }
      for (const restored of activeRestores) {
        if (
          products.some(
            (p) =>
              p.upid === restored.upid &&
              installedAt(p, restored.folder) &&
              version(p.installedVersion) ===
                restored.evidence.version
                  .split('.')
                  .slice(0, 3)
                  .map(Number)
                  .concat([0, 0, 0])
                  .slice(0, 3)
                  .join('.'),
          )
        ) {
          restored.validated = true;
        } else {
          restored.rollback();
          report.errors.push({
            title: restored.title,
            message:
              'Native Access did not recognise the restored original record; the new record was removed.',
          });
        }
      }
      for (const row of chosen.filter((r) => succeeded.has(r.upid) && r.state === 'canLocate'))
        if (!products.some((p) => p.upid === row.upid && installedAt(p, row.folder)))
          report.errors.push({
            title: row.title,
            message:
              'NI accepted the location request but has not confirmed this exact installation yet. Scan again after NI finishes activation.',
          });
      const verified = new Set(
        products
          .filter(
            (p) =>
              succeeded.has(p.upid) &&
              installedAt(p, chosen.find((r) => r.upid === p.upid)?.folder) &&
              version(p.installedVersion) === version(p.targetVersion),
          )
          .map((p) => p.upid),
      );
      const queue =
        (await api.call('activeDeploymentsRequest')).activeDeploymentsResponse.activeDeployments ||
        [];
      if (option('cancel-redundant') === 'true')
        for (const d of queue
          .filter((d) => d.state === 'STATE_DOWNLOAD_ENQUEUED')
          .concat(queue.filter((d) => d.state === 'STATE_DOWNLOAD_PAUSED'))) {
          if (!verified.has(d.upid)) continue;
          try {
            await api.call('cancelDownloadRequest', { deploymentId: d.deploymentId });
            report.actions.push({ operation: 'cancelRedundantDownload', title: d.title });
          } catch (e) {
            report.errors.push({ title: d.title, message: e.message });
          }
        }
      await finishRepairPause();
      rows = inventory(root, products, { connected: true });
      report.summary = summary(rows);
      report.cancelled = cancelled;
      const reportPath = saveReport();
      atomicJSON(path.join(vaultRoot(root), 'reports', operationID + '.json'), report);
      emit({
        type: 'result',
        command,
        root,
        connection,
        rows,
        summary: report.summary,
        reportPath,
        backupPath: report.backup,
        actions: report.actions,
        cancelled,
        errors: report.errors,
      });
    } else if (command === 'snapshot') {
      if (!connection.connected) throw Error(connection.message);
      releaseLock = acquireLock(root);
      report.backup = backupRecords(
        root,
        products.filter(
          (p) => p.installed && p.components?.some((c) => c.currentPath?.startsWith(root + '/')),
        ),
        { label: 'migration' },
      );
      report.receipts = await saveReceipts(root, products, {
        cancelled: () => cancelled,
        progress,
      });
      report.saved = report.receipts.filter((r) => r.state !== 'error').length;
      report.errors = report.receipts.filter((r) => r.state === 'error');
      const reportPath = saveReport();
      atomicJSON(path.join(vaultRoot(root), 'reports', operationID + '.json'), report);
      emit({
        type: 'result',
        command,
        root,
        saved: report.saved,
        errors: report.errors,
        reportPath,
        vault: vaultRoot(root),
      });
    } else if (command === 'verify') {
      const manifest = option('manifest');
      if (!manifest) throw Error('Choose the official Native Access Metalink manifest');
      const xml = fs.readFileSync(manifest, 'utf8');
      const files = parseMetalink(xml);
      report.manifestSha256 = hashBytes(xml);
      report.manifestSource =
        'User-selected local Metalink; its authenticity must be established separately';
      report.files = await verifyFiles(root, files, { cancelled: () => cancelled, progress });
      report.verified = report.files.filter((f) => f.state === 'verified').length;
      report.changedFileBytes = report.files
        .filter((f) => f.state !== 'verified')
        .reduce((n, f) => n + f.size, 0);
      const reportPath = saveReport();
      emit({
        type: 'result',
        command,
        verified: report.verified,
        total: files.length,
        changedFileBytes: report.changedFileBytes,
        reportPath,
      });
    } else throw Error('Unknown command');
  }
} catch (e) {
  report.errors.push(...rollbackPendingRestores(activeRestores));
  await finishRepairPause();
  report.error = e.message;
  report.cancelled = e.message === 'CANCELLED' || cancelled;
  const reportPath = saveReport();
  emit({ type: 'error', message: e.message, reportPath, cancelled: report.cancelled });
  process.exitCode = report.cancelled ? 130 : 1;
} finally {
  if (releaseLock) releaseLock();
  if (api) await api.close();
}
