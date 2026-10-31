import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import http from 'node:http';
import { cloudAccess, cloudRateLimit } from '../server/cloudAccess';
const app = express();
let verified = 0;
app.post(
  '/cloud',
  cloudAccess(async (token) => {
    verified++;
    if (token !== 'valid') throw new Error('Bad token');
    return 'test-uid';
  }),
  cloudRateLimit,
  (_req, res) => res.json({ ok: true }),
);
const server = http.createServer(app);
let base: string;
before(async () => {
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  process.env.GEMINI_API_KEY = 'test-only';
  process.env.FIREBASE_PROJECT_ID = 'test-project';
  process.env.CLOUD_ALLOWED_UIDS = 'test-uid';
});
after(() => new Promise<void>((resolve) => server.close(() => resolve())));
test('cloud is unavailable when deployment configuration is missing', async () => {
  delete process.env.GEMINI_API_KEY;
  assert.equal((await fetch(`${base}/cloud`, { method: 'POST' })).status, 503);
  process.env.GEMINI_API_KEY = 'test-only';
  assert.equal(verified, 0);
});
test('consent is required before token verification or provider access', async () => {
  assert.equal(
    (
      await fetch(`${base}/cloud`, {
        method: 'POST',
        headers: { Authorization: 'Bearer valid' },
      })
    ).status,
    403,
  );
  assert.equal(verified, 0);
});
test('missing and invalid authentication are rejected', async () => {
  assert.equal(
    (
      await fetch(`${base}/cloud`, {
        method: 'POST',
        headers: { 'X-Cloud-Consent': 'true' },
      })
    ).status,
    401,
  );
  assert.equal(
    (
      await fetch(`${base}/cloud`, {
        method: 'POST',
        headers: { 'X-Cloud-Consent': 'true', Authorization: 'Bearer invalid' },
      })
    ).status,
    401,
  );
});
test('authenticated consenting users are rate limited after 20 requests', async () => {
  const statuses: number[] = [];
  for (let index = 0; index < 21; index++)
    statuses.push(
      (
        await fetch(`${base}/cloud`, {
          method: 'POST',
          headers: { 'X-Cloud-Consent': 'true', Authorization: 'Bearer valid' },
        })
      ).status,
    );
  assert.deepEqual(statuses.slice(0, 20), Array(20).fill(200));
  assert.equal(statuses[20], 429);
});
