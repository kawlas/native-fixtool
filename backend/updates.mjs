// SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { version } from './native.mjs';
import { parseMetalink, safeChild, rootIdentity } from './core.mjs';

export const isNewer = (a, b) => {
  const av = String(a).split(/[.+]/).slice(0, 3).map(Number),
    bv = String(b).split(/[.+]/).slice(0, 3).map(Number);
  if (
    av.length !== 3 ||
    bv.length !== 3 ||
    [...av, ...bv].some((v) => !Number.isInteger(v) || v < 0)
  )
    return false;
  for (let i = 0; i < 3; i++) {
    if (av[i] !== bv[i]) return av[i] > bv[i];
  }
  return false;
};
export const contentPath = (p) =>
  p.components?.find((c) => c.name === 'COMPONENT_NAME_CONTENTDIR')?.currentPath || '';
export function updateCandidates(root, products, artifacts, queue = []) {
  return products
    .filter((p) => p.installed && isNewer(version(p.targetVersion), version(p.installedVersion)))
    .map((p) => {
      const folder = contentPath(p);
      let state = 'ready',
        reason = 'Official NI update of an existing content library';
      const matches = artifacts.filter(
        (a) =>
          a.upid === p.upid &&
          a.type === 'content' &&
          a.file_type === 'path' &&
          a.platform === 'all' &&
          a.version.split(/[.+]/).slice(0, 3).join('.') === version(p.targetVersion),
      );
      matches.sort(
        (a, b) =>
          (Date.parse(b.release_date) || 0) - (Date.parse(a.release_date) || 0) ||
          String(b.version).localeCompare(String(a.version), undefined, { numeric: true }),
      );
      const artifact = matches[0];
      if (!p.isOwned) {
        state = 'blocked';
        reason = 'Product is not owned by the signed-in account';
      } else if (p.type !== 'PRODUCT_TYPE_CONTENT') {
        state = 'nativeOnly';
        reason = 'Application or plug-in: use the original NI installer';
      } else if (
        p.isBroken ||
        !folder ||
        path.dirname(folder) !== root ||
        !fs.existsSync(folder) ||
        fs.realpathSync(folder) !== folder
      ) {
        state = 'blocked';
        reason = 'Repair this library location before updating';
      } else if (matches.length !== 1) {
        state = 'nativeOnly';
        reason = 'No unique exact target content manifest in the NI catalogue';
      }
      if (state === 'ready' && queue.some((d) => d.upid === p.upid)) {
        state = 'inProgress';
        reason = 'Native Access already has a job for this product';
      }
      return {
        id: p.upid,
        upid: p.upid,
        title: p.title,
        folder,
        installedVersion: version(p.installedVersion),
        targetVersion: version(p.targetVersion),
        state,
        reason,
        artifactID: artifact?.update_id || '',
        contentBytes: artifact?.filesize ?? null,
        audit: null,
        _artifact: artifact,
      };
    })
    .sort((a, b) => a.title.localeCompare(b.title));
}
export function contentManifest(xml, folder) {
  if (/<!DOCTYPE|<!ENTITY/i.test(xml)) throw Error('Unsupported XML entity declarations');
  const parsed = parseMetalink(xml);
  const raw = [
    ...xml.matchAll(/<(?:\w+:)?file\s+name="([^"]+)"[^>]*>([\s\S]*?)<\/(?:\w+:)?file>/g),
  ];
  const roots = new Set(parsed.map((f) => f.name.split('/')[0]));
  if (roots.size !== 1 || parsed.some((f) => !f.name.includes('/')))
    throw Error('Manifest must contain one library root');
  const manifestRoot = [...roots][0];
  if (manifestRoot !== path.basename(folder))
    throw Error(
      'The NI target folder differs from the registered library. Repair its location first.',
    );
  const names = new Set();
  return parsed.map((f, i) => {
    const name = f.name.slice(manifestRoot.length + 1);
    safeChild(folder, name);
    if (!name || names.has(name) || name.includes('\\'))
      throw Error('Duplicate or unsupported manifest path');
    names.add(name);
    const p = raw[i][2].match(
      /<(?:\w+:)?pieces\s+type="(sha-1|sha-256)"\s+length="(\d+)"[^>]*>([\s\S]*?)<\/(?:\w+:)?pieces>/,
    );
    let pieces = null;
    if (p) {
      const length = Number(p[2]),
        hashes = [...p[3].matchAll(/<(?:\w+:)?hash>([0-9a-f]+)<\/(?:\w+:)?hash>/gi)].map((m) =>
          m[1].toLowerCase(),
        );
      if (
        !Number.isSafeInteger(length) ||
        length < 1 ||
        length > 64 * 1024 * 1024 ||
        hashes.length !== Math.ceil(f.size / length) ||
        hashes.some((h) => h.length !== (p[1] === 'sha-1' ? 40 : 64))
      )
        throw Error('Unsupported piece manifest');
      pieces = { algorithm: p[1] === 'sha-1' ? 'sha1' : 'sha256', length, hashes };
    }
    return { ...f, name, pieces };
  });
}
function stamp(s) {
  return {
    device: String(s.dev),
    inode: String(s.ino),
    size: s.size,
    mtime: s.mtimeMs,
    ctime: s.ctimeMs,
  };
}
export async function auditUpdate(
  folder,
  files,
  { cancelled = () => false, progress = () => {} } = {},
) {
  const result = [];
  let readBytes = 0;
  const totalBytes = files.reduce((n, f) => n + f.size, 0);
  for (const [index, f] of files.entries()) {
    if (cancelled()) throw Error('CANCELLED');
    const file = safeChild(folder, f.name);
    let state = 'missing',
      local = null,
      matchingPieceBytes = 0;
    try {
      const s = fs.lstatSync(file);
      if (!s.isFile() || fs.realpathSync(file) !== file)
        throw Error('Symlink or non-regular update file: ' + f.name);
      local = stamp(s);
      // Read once: whole-file SHA-256 plus aligned vendor piece hashes.
      const whole = crypto.createHash('sha256');
      let piece = f.pieces ? crypto.createHash(f.pieces.algorithm) : null,
        pieceBytes = 0,
        pieceIndex = 0;
      for await (const data of fs.createReadStream(file, { highWaterMark: 4 * 1024 * 1024 })) {
        if (cancelled()) throw Error('CANCELLED');
        whole.update(data);
        readBytes += data.length;
        if (piece) {
          let offset = 0;
          while (offset < data.length) {
            const take = Math.min(data.length - offset, f.pieces.length - pieceBytes);
            piece.update(data.subarray(offset, offset + take));
            pieceBytes += take;
            offset += take;
            if (pieceBytes === f.pieces.length) {
              if (piece.digest('hex') === f.pieces.hashes[pieceIndex])
                matchingPieceBytes += Math.min(
                  pieceBytes,
                  Math.max(0, f.size - pieceIndex * f.pieces.length),
                );
              pieceIndex++;
              piece = crypto.createHash(f.pieces.algorithm);
              pieceBytes = 0;
            }
          }
        }
        progress({
          stage: 'auditUpdates',
          title: path.basename(folder) + ' · ' + f.name,
          current: index,
          total: files.length,
          readBytes,
          totalBytes,
        });
      }
      if (piece && pieceBytes) {
        if (piece.digest('hex') === f.pieces.hashes[pieceIndex])
          matchingPieceBytes += Math.min(
            pieceBytes,
            Math.max(0, f.size - pieceIndex * f.pieces.length),
          );
      }
      state =
        s.size === f.size && whole.digest('hex') === f.sha256
          ? 'verified'
          : s.size === f.size
            ? 'differentHash'
            : 'differentSize';
      if (JSON.stringify(local) !== JSON.stringify(stamp(fs.statSync(file))))
        throw Error('File changed during update audit: ' + f.name);
      if (state === 'verified' && f.pieces && matchingPieceBytes !== f.size)
        throw Error('Inconsistent vendor file and piece hashes');
    } catch (e) {
      if (e.code !== 'ENOENT') throw e;
    }
    result.push({
      name: f.name,
      size: f.size,
      state,
      matchingPieceBytes: state === 'verified' ? f.size : matchingPieceBytes,
      local,
    });
  }
  const matchingFileBytes = result
    .filter((f) => f.state === 'verified')
    .reduce((n, f) => n + f.size, 0);
  const matchingPieceBytes = result.reduce((n, f) => n + f.matchingPieceBytes, 0);
  return {
    date: new Date().toISOString(),
    totalFiles: files.length,
    matchingFiles: result.filter((f) => f.state === 'verified').length,
    totalBytes,
    matchingFileBytes,
    matchingPieceBytes,
    changedFileBytes: totalBytes - matchingFileBytes,
    estimatedTransferBytes: totalBytes - matchingPieceBytes,
    files: result,
  };
}
export function updatePlan(root, rows, nativeVersion) {
  return {
    schema: 1,
    kind: 'updates',
    date: new Date().toISOString(),
    root: rootIdentity(root),
    nativeVersion,
    rows: rows.map(({ _artifact, ...r }) => r),
  };
}
export function assertUpdateSelection(plan, selected, fresh) {
  if (!Array.isArray(selected) || !selected.length || selected.length !== new Set(selected).size)
    throw Error('Select updates from the reviewed plan');
  return selected.map((id) => {
    const old = plan.rows.find((r) => r.id === id),
      now = fresh.find((r) => r.id === id);
    if (
      !old ||
      !now ||
      old.state !== 'ready' ||
      now.state !== 'ready' ||
      ['upid', 'folder', 'installedVersion', 'targetVersion', 'artifactID'].some(
        (k) => old[k] !== now[k],
      )
    )
      throw Error('Update state changed. Check updates again.');
    return now;
  });
}
export const publicUpdates = (rows) =>
  rows.map(({ _artifact, ...r }) => ({
    ...r,
    audit: r.audit
      ? Object.fromEntries(Object.entries(r.audit).filter(([k]) => k !== 'files'))
      : null,
  }));

export function assertNoDuplicateUpdates(rows, queue) {
  if (queue.some((d) => rows.some((r) => r.upid === d.upid)))
    throw Error(
      'A selected product already has a Native Access job. Finish or review that job before starting another update.',
    );
}
export async function requestOfficialUpdate(api, row) {
  const response = (
    await api.call('startDeploymentsRequest', {
      deployments: [{ upid: row.upid, type: 'DEPLOYMENT_TYPE_UPDATE' }],
    })
  ).startDeploymentsResponse;
  const r = response?.results?.[0];
  if (r?.error || !r?.deploymentId || r.upid !== row.upid)
    throw Error('Native Access did not accept this update');
  return r.deploymentId;
}

export function sessionStatus(session, products, queue) {
  return session.deployments.map((d) => {
    const p = products.find((p) => p.upid === d.upid),
      active = queue.find((q) => q.deploymentId === d.deploymentId);
    const confirmed =
      p?.installed &&
      !p.isBroken &&
      d.folder &&
      contentPath(p) === d.folder &&
      version(p.installedVersion) === d.targetVersion;
    return {
      upid: d.upid,
      title: d.title,
      targetVersion: d.targetVersion,
      installedVersion: version(p?.installedVersion),
      state: active?.state || (confirmed ? 'confirmed' : 'notConfirmed'),
      progress: active?.progress || 0,
    };
  });
}
