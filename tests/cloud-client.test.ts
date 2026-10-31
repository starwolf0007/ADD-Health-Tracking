import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  createCloudTransport,
  type CloudUser,
} from '../src/lib/cloudTransport';
function fixture() {
  let enabled = false;
  let uid = 'a';
  let fetchCount = 0;
  let tokenCount = 0;
  let getToken = async () => {
    tokenCount++;
    return 'id-token';
  };
  let user: CloudUser | null = {
    uid,
    isAnonymous: false,
    getIdToken: () => getToken(),
  };
  const transport = createCloudTransport({
    enabled: () => enabled,
    user: () => user,
    scope: () => uid,
    fetch: async (_input, init) => {
      fetchCount++;
      assert.equal(
        (init?.headers as Record<string, string>).Authorization,
        'Bearer id-token',
      );
      return new Response('{}');
    },
  });
  return {
    transport,
    enable: () => {
      enabled = true;
    },
    disable: () => {
      enabled = false;
    },
    changeAccount: () => {
      uid = 'b';
      user = { uid, isAnonymous: false, getIdToken: async () => 'other' };
    },
    setUser: (value: CloudUser | null) => {
      user = value;
    },
    setToken: (callback: () => Promise<string>) => {
      getToken = callback;
    },
    counts: () => ({ fetchCount, tokenCount }),
  };
}
test('cloud off blocks requests before retrieving a token or making a network request', async () => {
  const f = fixture();
  await assert.rejects(
    f.transport.request('/api/gemini/chat', {}),
    /Cloud Gemini is off/,
  );
  assert.deepEqual(f.counts(), { fetchCount: 0, tokenCount: 0 });
});
test('signed-out and anonymous clients cannot request cloud inference', async () => {
  const f = fixture();
  f.enable();
  f.setUser(null);
  await assert.rejects(f.transport.request('/api/gemini/chat', {}), /Sign in/);
  f.setUser({
    uid: 'a',
    isAnonymous: true,
    getIdToken: async () => 'anonymous',
  });
  await assert.rejects(f.transport.request('/api/gemini/chat', {}), /Sign in/);
  assert.equal(f.counts().fetchCount, 0);
});
test('consent revoked while retrieving a token blocks the subsequent upload', async () => {
  const f = fixture();
  f.enable();
  f.setToken(async () => {
    f.disable();
    return 'id-token';
  });
  await assert.rejects(
    f.transport.request('/api/gemini/transcribe', {}),
    /Cloud Gemini is off/,
  );
  assert.equal(f.counts().fetchCount, 0);
});
test('switching accounts while retrieving a token blocks the subsequent upload', async () => {
  const f = fixture();
  f.enable();
  f.setToken(async () => {
    f.changeAccount();
    return 'id-token';
  });
  await assert.rejects(
    f.transport.request('/api/gemini/search', {}),
    /Account changed/,
  );
  assert.equal(f.counts().fetchCount, 0);
});
test('consenting signed-in client sends a Firebase bearer token', async () => {
  const f = fixture();
  f.enable();
  assert.equal((await f.transport.request('/api/gemini/chat', {})).status, 200);
  assert.deepEqual(f.counts(), { fetchCount: 1, tokenCount: 1 });
});
