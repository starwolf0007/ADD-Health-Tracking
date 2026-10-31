import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import {
  setStorageUser,
  taskStorage,
  noteStorage,
  settingsStorage,
  hevyStorage,
  routineStorage,
  readOutbox,
  applyRemoteRecords,
  acknowledgeWrite,
  resetCurrentLocalData,
} from '../src/lib/storage';
import {
  startAccountSync,
  type SyncAdapter,
  type SyncStatus,
} from '../src/lib/sync';
import type { Task, Note } from '../src/types';
const values = new Map<string, string>();
Object.defineProperty(globalThis, 'localStorage', {
  value: {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => {
      values.set(key, value);
    },
    removeItem: (key: string) => {
      values.delete(key);
    },
  },
  configurable: true,
});
const task = (title = 'Private A'): Task => ({
  id: 'task-a',
  title,
  energy: 'low',
  status: 'pending',
  createdAt: '2026-10-31',
  isQuickWin: true,
});
const note: Note = {
  id: 'note-a',
  body: 'Private note',
  pinned: false,
  createdAt: '2026-10-31',
  updatedAt: '2026-10-31',
};
const tick = () => new Promise((resolve) => setTimeout(resolve, 0));
beforeEach(() => {
  values.clear();
  setStorageUser(null);
});

test('new accounts do not inherit guest data or another account’s settings and API key', () => {
  taskStorage.save(task('Guest'));
  setStorageUser('a');
  assert.deepEqual(taskStorage.getAll(), []);
  assert.deepEqual(routineStorage.getAll(), []);
  taskStorage.save(task());
  noteStorage.save(note);
  hevyStorage.saveApiKey('private-key');
  settingsStorage.save({ cloudGemini: true });
  setStorageUser('b');
  assert.deepEqual(taskStorage.getAll(), []);
  assert.deepEqual(noteStorage.getAll(), []);
  assert.equal(hevyStorage.getApiKey(), '');
  assert.equal(settingsStorage.get().cloudGemini, false);
  setStorageUser('a');
  assert.equal(taskStorage.getAll()[0].title, 'Private A');
  setStorageUser(null);
  assert.equal(
    taskStorage.getAll().find((item) => item.id === 'task-a')?.title,
    'Guest',
  );
});
test('task completion, pause and note pinning are queued as real local edits', () => {
  setStorageUser('a');
  taskStorage.save(task());
  taskStorage.complete('task-a');
  assert.equal(
    (readOutbox('a', 'tasks')['task-a'].value as Task).status,
    'completed',
  );
  taskStorage.pauseTask('task-a', 'Open document');
  assert.equal(
    (readOutbox('a', 'tasks')['task-a'].value as Task).reentryNote?.nextAction,
    'Open document',
  );
  noteStorage.save(note);
  noteStorage.togglePin('note-a');
  assert.equal((readOutbox('a', 'notes')['note-a'].value as Note).pinned, true);
});
test('pending edits and deletes survive stale remote snapshots without echoing remote records', () => {
  setStorageUser('a');
  taskStorage.save(task('Offline edit'));
  applyRemoteRecords('a', 'tasks', [task('Stale server edit')]);
  assert.equal(taskStorage.getAll()[0].title, 'Offline edit');
  taskStorage.delete('task-a');
  applyRemoteRecords('a', 'tasks', [task()]);
  assert.deepEqual(taskStorage.getAll(), []);
  assert.equal(readOutbox('a', 'tasks')['task-a'].value, null);
  applyRemoteRecords('a', 'notes', [note]);
  assert.deepEqual(readOutbox('a', 'notes'), {});
});
test('late account A snapshot cannot enter account B cache', () => {
  setStorageUser('b');
  applyRemoteRecords('a', 'tasks', [task()]);
  assert.deepEqual(taskStorage.getAll(), []);
});
test('acknowledging an older revision never clears a newer local edit', () => {
  setStorageUser('a');
  taskStorage.save(task());
  const revision = readOutbox('a', 'tasks')['task-a'].revision;
  taskStorage.save(task('Newer'));
  acknowledgeWrite('a', 'tasks', 'task-a', revision);
  assert.equal(
    (readOutbox('a', 'tasks')['task-a'].value as Task).title,
    'Newer',
  );
});
test('reset is scoped and retains offline writes', () => {
  setStorageUser('a');
  taskStorage.save(task());
  setStorageUser('b');
  taskStorage.save(task('B'));
  resetCurrentLocalData();
  assert.ok(readOutbox('b', 'tasks')['task-a']);
  setStorageUser('a');
  assert.equal(taskStorage.getAll()[0].title, 'Private A');
});
test('failed uploads retain durable writes; restarting sync retries them', async () => {
  setStorageUser('a');
  taskStorage.save(task());
  const statuses: SyncStatus[] = [];
  let stop = startAccountSync(
    'a',
    {
      listen: () => () => {},
      write: async () => {
        throw new Error('Offline');
      },
    },
    (status) => statuses.push(status),
  );
  await tick();
  assert.equal(statuses.at(-1), 'error');
  assert.ok(readOutbox('a', 'tasks')['task-a']);
  stop();
  const writes: unknown[] = [];
  stop = startAccountSync(
    'a',
    {
      listen: (_name, receive) => {
        receive([], false);
        return () => {};
      },
      write: async (...args) => {
        writes.push(args);
      },
    },
    (status) => statuses.push(status),
  );
  await tick();
  assert.equal(writes.length, 1);
  assert.deepEqual(readOutbox('a', 'tasks'), {});
  assert.equal(statuses.at(-1), 'synced');
  stop();
});
test('new edits during upload are sent after the in-flight write', async () => {
  setStorageUser('a');
  taskStorage.save(task('First'));
  let release!: () => void;
  const first = new Promise<void>((resolve) => {
    release = resolve;
  });
  const titles: string[] = [];
  const stop = startAccountSync(
    'a',
    {
      listen: () => () => {},
      write: async (_name, _id, value) => {
        titles.push((value as Task).title);
        if (titles.length === 1) await first;
      },
    },
    () => {},
  );
  taskStorage.save(task('Second'));
  release();
  await tick();
  assert.deepEqual(titles, ['First', 'Second']);
  assert.deepEqual(readOutbox('a', 'tasks'), {});
  stop();
});
test('switching accounts during a pending upload stops subsequent writes and status changes', async () => {
  setStorageUser('a');
  taskStorage.save(task());
  noteStorage.save(note);
  let release!: () => void;
  const pending = new Promise<void>((resolve) => {
    release = resolve;
  });
  let count = 0;
  const stop = startAccountSync(
    'a',
    {
      listen: () => () => {},
      write: async () => {
        count++;
        await pending;
      },
    },
    () => {},
  );
  setStorageUser('b');
  release();
  await tick();
  assert.equal(count, 1);
  assert.ok(readOutbox('a', 'notes')['note-a']);
  stop();
});
test('cached snapshots alone cannot mark a session synced', async () => {
  setStorageUser('a');
  const statuses: SyncStatus[] = [];
  const adapter: SyncAdapter = {
    listen: (_name, receive) => {
      receive([], true);
      return () => {};
    },
    write: async () => {},
  };
  const stop = startAccountSync('a', adapter, (status) =>
    statuses.push(status),
  );
  await tick();
  assert.equal(statuses.at(-1), 'syncing');
  stop();
});

test('offline startup with an empty Firestore cache preserves previously downloaded local records', async () => {
  setStorageUser('a');
  taskStorage.save(task('Previously synced'));
  const revision = readOutbox('a', 'tasks')['task-a'].revision;
  acknowledgeWrite('a', 'tasks', 'task-a', revision);
  const stop = startAccountSync(
    'a',
    {
      listen: (_name, receive) => {
        receive([], true);
        return () => {};
      },
      write: async () => {},
    },
    () => {},
  );
  await tick();
  assert.equal(taskStorage.getAll()[0].title, 'Previously synced');
  stop();
});
test('an empty outbox does not erase a listener permission error', async () => {
  setStorageUser('a');
  const statuses: SyncStatus[] = [];
  const stop = startAccountSync(
    'a',
    {
      listen: (_name, _receive, fail) => {
        fail();
        return () => {};
      },
      write: async () => {},
    },
    (status) => statuses.push(status),
  );
  await tick();
  assert.equal(statuses.at(-1), 'error');
  stop();
});
