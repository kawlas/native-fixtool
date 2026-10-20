// SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { atomicJSON, vaultRoot, safeChild, hashFile, verifyFiles } from './core.mjs';
export const systemRecords = '/Users/Shared/Native Instruments/installed_products';
export function recordPath(title, base = systemRecords) {
  if (path.basename(title) !== title) throw Error('Unsafe product name');
  return path.join(base, title + '.json');
}
export function findOriginalRecord(product, base = systemRecords) {
  const preferred = recordPath(product.title, base);
  if (fs.existsSync(preferred))
    return { file: preferred, name: product.title, record: JSON.parse(fs.readFileSync(preferred)) };
  const dir = product.components?.find((c) => c.name === 'COMPONENT_NAME_CONTENTDIR')?.currentPath;
  const matches = [];
  if (dir && fs.existsSync(base))
    for (const name of fs.readdirSync(base).filter((n) => n.endsWith('.json'))) {
      try {
        const file = path.join(base, name),
          record = JSON.parse(fs.readFileSync(file));
        if (record.ContentDir === dir) matches.push({ file, name: name.slice(0, -5), record });
      } catch {
        // An unrelated unreadable record is not evidence for this product.
      }
    }
  if (matches.length !== 1)
    throw Error('The original NI record could not be matched uniquely for ' + product.title);
  return matches[0];
}
function validRecord(record) {
  return (
    record &&
    typeof record.ContentDir === 'string' &&
    typeof record.ContentVersion === 'string' &&
    /^\d+(?:\.\d+){1,3}$/.test(record.ContentVersion) &&
    Object.keys(record).every((k) => ['ContentDir', 'ContentVersion'].includes(k))
  );
}
export function backupRecords(
  root,
  products,
  { recordsRoot = systemRecords, label = 'repair' } = {},
) {
  const stamp = new Date().toISOString().replaceAll(':', '-');
  const dir = path.join(vaultRoot(root), 'backups', stamp + '-' + label);
  fs.mkdirSync(dir, { recursive: true });
  const saved = [];
  for (const p of products) {
    let source;
    try {
      source = findOriginalRecord(p, recordsRoot);
    } catch {
      continue;
    }
    const file = source.file;
    if (fs.existsSync(file)) {
      const b = fs.readFileSync(file);
      JSON.parse(b);
      fs.writeFileSync(path.join(dir, p.upid + '.json'), b, { mode: 0o600, flag: 'wx' });
      saved.push({
        title: p.title,
        upid: p.upid,
        file: p.upid + '.json',
        originalRecordName: source.name,
      });
    }
  }
  atomicJSON(path.join(dir, 'index.json'), { date: new Date().toISOString(), products: saved });
  return dir;
}
async function fileInventory(folder, { cancelled, progress }) {
  const files = [];
  async function walk(dir) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (cancelled()) throw Error('CANCELLED');
      if (e.name === '.DS_Store' || e.name.endsWith('.aria2')) continue;
      const p = path.join(dir, e.name);
      if (e.isDirectory()) await walk(p);
      else if (e.isFile()) {
        const before = fs.statSync(p),
          sha256 = await hashFile(p, { cancelled }),
          after = fs.statSync(p);
        if (before.size !== after.size || before.mtimeMs !== after.mtimeMs)
          throw Error('File changed while being read: ' + p);
        files.push({ name: path.relative(folder, p), size: after.size, sha256 });
        if (files.length % 20 === 0)
          progress({
            stage: 'snapshotFiles',
            title: path.basename(folder),
            current: files.length,
            total: 0,
          });
      } else throw Error('Cannot snapshot a symlink or non-regular file: ' + p);
    }
  }
  await walk(folder);
  return files;
}
export async function saveReceipts(
  root,
  products,
  { recordsRoot = systemRecords, cancelled = () => false, progress = () => {} } = {},
) {
  const eligible = products.filter(
    (p) =>
      p.type === 'PRODUCT_TYPE_CONTENT' &&
      p.installed &&
      !p.isBroken &&
      p.activationState === 'ACTIVATION_STATE_ACTIVATED' &&
      p.components?.some(
        (c) => c.name === 'COMPONENT_NAME_CONTENTDIR' && c.currentPath.startsWith(root + '/'),
      ),
  );
  const result = [];
  for (const [index, p] of eligible.entries()) {
    if (cancelled()) throw Error('CANCELLED');
    const folder = p.components.find((c) => c.name === 'COMPONENT_NAME_CONTENTDIR').currentPath;
    if (!fs.existsSync(folder)) continue;
    progress({ stage: 'snapshot', title: p.title, current: index + 1, total: eligible.length });
    try {
      const source = findOriginalRecord(p, recordsRoot);
      const record = source.record;
      if (!validRecord(record) || record.ContentDir !== folder)
        throw Error('Unsupported original record format');
      const descriptors = fs.readdirSync(folder).filter((n) => n.endsWith('.nicnt'));
      const fullFiles = descriptors.length === 0;
      const receiptFile = path.join(vaultRoot(root), 'receipts', p.upid + '.json');
      let prior = null;
      try {
        prior = JSON.parse(fs.readFileSync(receiptFile));
      } catch {
        // A missing/unreadable prior snapshot must be replaced from current authentic NI data.
      }
      if (
        !fullFiles &&
        prior?.schema === 1 &&
        prior.fullFiles === fullFiles &&
        prior.record.ContentVersion === record.ContentVersion &&
        prior.folder === path.basename(folder)
      ) {
        result.push({ title: p.title, state: 'alreadySaved', fullFiles });
        continue;
      }
      const files = fullFiles ? await fileInventory(folder, { cancelled, progress }) : [];
      const receipt = {
        schema: 1,
        date: new Date().toISOString(),
        upid: p.upid,
        title: p.title,
        folder: path.basename(folder),
        originalPath: folder,
        recordName: source.name,
        record,
        installedVersion: p.installedVersion,
        fullFiles,
        files,
        provenance: fullFiles
          ? 'Exact SHA-256 snapshot of files in an installation recognised and activated by NTKDaemon. Not a vendor-signed manifest.'
          : 'Authentic NI record retained for reference. Restore uses Native Access and the product descriptor.',
      };
      atomicJSON(receiptFile, receipt);
      result.push({ title: p.title, state: 'saved', fullFiles, fileCount: files.length });
    } catch (e) {
      if (String(e.message) === 'CANCELLED') throw e;
      result.push({ title: p.title, state: 'error', message: e.message });
    }
  }
  return result;
}
export async function restoreReceipt(
  root,
  row,
  product,
  {
    recordsRoot = systemRecords,
    cancelled = () => false,
    progress = () => {},
    validateRoot = () => {},
  } = {},
) {
  const file = safeChild(path.join(vaultRoot(root), 'receipts'), row.upid + '.json');
  const receipt = JSON.parse(fs.readFileSync(file));
  if (
    (receipt.recordName && receipt.recordName !== product.title) ||
    receipt.schema !== 1 ||
    !receipt.fullFiles ||
    !receipt.files?.length ||
    !validRecord(receipt.record) ||
    receipt.upid !== product.upid ||
    receipt.title !== product.title ||
    receipt.folder !== path.basename(row.folder) ||
    !product.isOwned ||
    product.installed
  )
    throw Error('The original receipt cannot safely be restored');
  const results = await verifyFiles(row.folder, receipt.files, { cancelled, progress });
  if (results.some((f) => f.state !== 'verified'))
    throw Error('Files differ from the saved installation. No registration was restored.');
  if (cancelled()) throw Error('CANCELLED');
  validateRoot();
  const dest = recordPath(product.title, recordsRoot);
  if (fs.existsSync(dest))
    throw Error('A registration record already exists; it will not be overwritten.');
  fs.mkdirSync(recordsRoot, { recursive: true });
  const text = JSON.stringify({ ...receipt.record, ContentDir: row.folder }) + '\n';
  const staging = path.join(recordsRoot, '.library-bridge-' + crypto.randomUUID() + '.tmp');
  try {
    fs.writeFileSync(staging, text, { flag: 'wx', mode: 0o644 });
    fs.linkSync(staging, dest);
  } finally {
    if (fs.existsSync(staging)) fs.unlinkSync(staging);
  }
  return {
    dest,
    text,
    evidence: {
      receiptDate: receipt.date,
      filesVerified: results.length,
      version: receipt.record.ContentVersion,
    },
    rollback() {
      if (fs.existsSync(dest) && fs.readFileSync(dest, 'utf8') === text) fs.unlinkSync(dest);
    },
  };
}
