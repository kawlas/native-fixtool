// SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
import { spawn } from 'node:child_process';

// Credentials stay in this process, travel only to the fixed NI API origin,
// and never enter command-line arguments, reports, URLs or saved manifests.
async function getMetadata(url, token, { cancelled = () => false } = {}) {
  const u = new URL(url);
  if (
    u.origin !== 'https://api.native-instruments.com' ||
    !u.pathname.startsWith('/v2/download/') ||
    u.search ||
    u.hash
  )
    throw Error('Unexpected NI metadata endpoint');
  if (!token || /[\r\n"\\]/.test(token)) throw Error('Sign into Native Access first');
  return await new Promise((resolve, reject) => {
    const child = spawn(
      '/usr/bin/curl',
      [
        '--disable',
        '--silent',
        '--fail',
        '--connect-timeout',
        '8',
        '--max-time',
        '40',
        '--proto',
        '=https',
        '--max-filesize',
        '30000000',
        '--header',
        'Accept: application/metalink4+xml, application/json',
        '--config',
        '-',
        u.href,
      ],
      { stdio: ['pipe', 'pipe', 'pipe'] },
    );
    const chunks = [];
    let count = 0,
      tooLarge = false;
    child.stdin.on('error', () => {});
    child.stdin.end('header = "Authorization: Bearer ' + token + '"\n');
    child.stdout.on('data', (b) => {
      count += b.length;
      if (count > 30000000) {
        tooLarge = true;
        child.kill();
      } else chunks.push(b);
    });
    child.stderr.resume();
    const timer = setInterval(() => {
      if (cancelled()) child.kill();
    }, 150);
    child.on('error', () => {
      clearInterval(timer);
      reject(Error('Cannot start the system network client'));
    });
    child.on('close', (code) => {
      clearInterval(timer);
      if (cancelled()) reject(Error('CANCELLED'));
      else if (tooLarge) reject(Error('NI metadata exceeds the supported size'));
      else if (code !== 0)
        reject(
          Error('NI metadata request failed (network/session). Sign into Native Access and retry.'),
        );
      else resolve(Buffer.concat(chunks).toString('utf8'));
    });
  });
}
export async function updateCloud(api, options = {}) {
  const token = (await api.call('auth0AccessTokenRequest')).auth0AccessTokenResponse?.accessToken;
  if (!token) throw Error('Sign into Native Access first');
  return {
    async catalog() {
      const d = JSON.parse(
        await getMetadata(
          'https://api.native-instruments.com/v2/download/me/content',
          token,
          options,
        ),
      );
      if (!Array.isArray(d.artifacts)) throw Error('Unsupported NI catalogue format');
      return d.artifacts;
    },
    async manifest(artifact) {
      if (
        !/^[0-9a-f-]{36}$/i.test(artifact.upid) ||
        !/^[0-9a-f-]{36}$/i.test(artifact.update_id) ||
        artifact.url !== `/links/${artifact.upid}/${artifact.update_id}`
      )
        throw Error('Unsupported NI manifest identity');
      return await getMetadata(
        'https://api.native-instruments.com/v2/download' + artifact.url,
        token,
        options,
      );
    },
  };
}
