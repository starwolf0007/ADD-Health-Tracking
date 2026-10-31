import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
import { createServer } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';
import WebSocket from 'ws';
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
      if ((await fetch(`${base}/api/health`)).ok) {
        ready = true;
        break;
      }
    } catch {}
    if (child.exitCode !== null) throw new Error(`Server exited: ${output}`);
    await delay(100);
  }
  assert.ok(ready, 'Production server must start without cloud credentials');
  for (const route of ['/', '/today', '/settings']) {
    const response = await fetch(`${base}${route}`);
    assert.equal(response.status, 200);
    assert.match(await response.text(), /<div id="root"><\/div>/);
  }
  const html = await (await fetch(base)).text();
  const script = html.match(/src="([^\"]+\.js)"/)[1];
  assert.equal((await fetch(`${base}${script}`)).status, 200);
  for (const route of ['chat', 'search', 'maps', 'transcribe', 'live-ticket']) {
    assert.equal(
      (
        await fetch(`${base}/api/gemini/${route}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: '{}',
        })
      ).status,
      503,
    );
  }
  assert.equal((await fetch(`${base}/api/unknown`)).status, 404);
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
  console.log(
    'Production smoke passed: startup, SPA routes, JS asset, five closed cloud routes, API 404, unauthenticated voice rejection.',
  );
} finally {
  child.kill();
  await new Promise((resolve) => child.once('exit', resolve));
}
