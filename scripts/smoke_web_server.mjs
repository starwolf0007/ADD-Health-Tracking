import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';
import crypto from 'node:crypto';
import WebSocket from 'ws';

// Generate dynamic, ephemeral test credentials for this test run (never hardcoded)
const ephemeralPass = crypto.randomBytes(16).toString('hex');
const validAuthHeader = `Basic ${Buffer.from(`preview:${ephemeralPass}`).toString('base64')}`;
const invalidAuthHeader = `Basic ${Buffer.from('preview:wrong-password').toString('base64')}`;

const probe = createServer();
await new Promise((resolve) => probe.listen(0, '127.0.0.1', resolve));
const port = probe.address().port;
await new Promise((resolve) => probe.close(resolve));

const child = spawn(process.execPath, ['--import', 'tsx', 'server.ts'], {
  env: {
    ...process.env,
    NODE_ENV: 'production',
    PORT: String(port),
    GEMINI_API_KEY: '',
    FIREBASE_PROJECT_ID: '',
    CLOUD_ALLOWED_UIDS: '',
    PREVIEW_USER: 'preview',
    PREVIEW_PASS: ephemeralPass,
  },
  stdio: ['ignore', 'pipe', 'pipe'],
});

let output = '';
child.stdout.on('data', (data) => {
  output += data;
});
child.stderr.on('data', (data) => {
  output += data;
});

const base = `http://127.0.0.1:${port}`;

try {
  let ready = false;
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      const probeRes = await fetch(`${base}/api/health`, {
        headers: { Authorization: validAuthHeader },
      });
      if (probeRes.ok) {
        ready = true;
        break;
      }
    } catch {}
    if (child.exitCode !== null) throw new Error(`Server exited: ${output}`);
    await delay(100);
  }
  assert.ok(ready, 'Production server must start and accept valid Basic Auth credentials');

  // 1. Verify unauthenticated request rejection (401 + WWW-Authenticate header, no UI leak)
  const unauth = await fetch(`${base}/`);
  assert.equal(unauth.status, 401);
  assert.equal(
    unauth.headers.get('www-authenticate'),
    'Basic realm="NeuroFlow Preview", charset="UTF-8"',
  );
  assert.equal(await unauth.text(), 'Unauthorized');

  // 2. Verify invalid credentials rejection (401 + WWW-Authenticate header)
  const badAuth = await fetch(`${base}/`, {
    headers: { Authorization: invalidAuthHeader },
  });
  assert.equal(badAuth.status, 401);
  assert.equal(
    badAuth.headers.get('www-authenticate'),
    'Basic realm="NeuroFlow Preview", charset="UTF-8"',
  );
  assert.equal(await badAuth.text(), 'Unauthorized');

  // 3. Verify authenticated SPA routes
  for (const route of ['/', '/today', '/settings']) {
    const response = await fetch(`${base}${route}`, {
      headers: { Authorization: validAuthHeader },
    });
    assert.equal(response.status, 200);
    assert.match(await response.text(), /<div id="root"><\/div>/);
  }

  // 4. Verify authenticated static asset serving
  const html = await (await fetch(base, { headers: { Authorization: validAuthHeader } })).text();
  const scriptMatch = html.match(/src="([^\"]+\.js)"/);
  assert.ok(scriptMatch, 'Should find JS script tag in index.html');
  const script = scriptMatch[1];
  assert.equal(
    (await fetch(`${base}${script}`, { headers: { Authorization: validAuthHeader } })).status,
    200,
  );

  // 5. Verify unconfigured cloud routes return 503 when authenticated
  for (const route of ['chat', 'search', 'maps', 'transcribe', 'live-ticket']) {
    assert.equal(
      (
        await fetch(`${base}/api/gemini/${route}`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: validAuthHeader,
          },
          body: '{}',
        })
      ).status,
      503,
    );
  }

  // 6. Verify unknown API routes return 404 when authenticated
  assert.equal(
    (await fetch(`${base}/api/unknown`, { headers: { Authorization: validAuthHeader } })).status,
    404,
  );

  // 7. Verify voice WebSocket rejection without grant ticket
  await new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/api/live-ws`, {
      origin: base,
    });
    ws.on('open', () => {
      ws.close();
      reject(new Error('Unauthenticated voice socket was accepted'));
    });
    ws.on('unexpected-response', (_req, res) => {
      try {
        assert.equal(res.statusCode, 401);
        res.resume();
        resolve();
      } catch (error) {
        reject(error);
      }
    });
    ws.on('error', reject);
  });

  // 8. Verify fail-closed behavior: server with empty PREVIEW_PASS denies all requests with 401
  const failClosedProbe = createServer();
  await new Promise((resolve) => failClosedProbe.listen(0, '127.0.0.1', resolve));
  const failClosedPort = failClosedProbe.address().port;
  await new Promise((resolve) => failClosedProbe.close(resolve));

  const failClosedChild = spawn(process.execPath, ['--import', 'tsx', 'server.ts'], {
    env: {
      ...process.env,
      NODE_ENV: 'production',
      PORT: String(failClosedPort),
      GEMINI_API_KEY: '',
      FIREBASE_PROJECT_ID: '',
      CLOUD_ALLOWED_UIDS: '',
      PREVIEW_USER: 'preview',
      PREVIEW_PASS: '', // empty -> must fail closed
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  try {
    const failClosedBase = `http://127.0.0.1:${failClosedPort}`;
    let failClosedReady = false;
    for (let attempt = 0; attempt < 50; attempt++) {
      try {
        const res = await fetch(`${failClosedBase}/api/health`, {
          headers: { Authorization: validAuthHeader },
        });
        if (res.status === 401) {
          failClosedReady = true;
          break;
        }
      } catch {}
      await delay(100);
    }
    assert.ok(failClosedReady, 'Server with empty PREVIEW_PASS must start and fail-closed with 401');

    const denied = await fetch(`${failClosedBase}/`, {
      headers: { Authorization: validAuthHeader },
    });
    assert.equal(denied.status, 401);
    assert.equal(
      denied.headers.get('www-authenticate'),
      'Basic realm="NeuroFlow Preview", charset="UTF-8"',
    );
    assert.equal(await denied.text(), 'Unauthorized');
  } finally {
    failClosedChild.kill();
    await new Promise((resolve) => failClosedChild.once('exit', resolve));
  }

  console.log(
    'Production smoke passed: basic auth gate (unauth 401, bad auth 401, fail-closed on empty PREVIEW_PASS), startup, SPA routes, JS asset, five closed cloud routes, API 404, unauthenticated voice rejection.',
  );
} finally {
  child.kill();
  await new Promise((resolve) => child.once('exit', resolve));
}
