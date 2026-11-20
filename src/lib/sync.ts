import {
  acknowledgeWrite,
  applyRemoteRecords,
  getStorageUser,
  readOutbox,
  subscribeStorage,
  type SyncCollection,
  type SyncRecord,
} from './storage';

export type SyncStatus = 'idle' | 'syncing' | 'synced' | 'error';
export interface SyncAdapter {
  listen(
    collection: SyncCollection,
    onRecords: (records: SyncRecord[], fromCache: boolean) => void,
    onError: () => void,
  ): () => void;
  write(
    collection: SyncCollection,
    id: string,
    value: SyncRecord | null,
  ): Promise<void>;
}

// One serialized outbox per account. Writes survive reload/offline; late callbacks
// cannot mutate a different account. Concurrent device edits use last server write.
export function startAccountSync(
  uid: string,
  adapter: SyncAdapter,
  status: (value: SyncStatus) => void,
) {
  let stopped = false;
  let flushing = false;
  let uploadFailed = false;
  let listenerFailed = false;
  const serverSnapshots = new Set<SyncCollection>();
  const collections: SyncCollection[] = ['tasks', 'notes'];
  const active = () => !stopped && getStorageUser() === uid;
  const hasPending = () =>
    collections.some((name) => Object.keys(readOutbox(uid, name)).length > 0);
  const report = () => {
    if (active())
      status(
        uploadFailed || listenerFailed
          ? 'error'
          : serverSnapshots.size === 2 && !hasPending()
            ? 'synced'
            : 'syncing',
      );
  };
  const flush = async () => {
    if (!active() || flushing) return;
    flushing = true;
    try {
      while (active() && hasPending()) {
        for (const collection of collections) {
          for (const [id, write] of Object.entries(
            readOutbox(uid, collection),
          )) {
            if (!active()) return;
            await adapter.write(collection, id, write.value);
            // A new local edit during the request must remain queued.
            acknowledgeWrite(uid, collection, id, write.revision);
          }
        }
      }
      uploadFailed = false;
    } catch {
      uploadFailed = true;
    } finally {
      flushing = false;
      report();
    }
  };
  const unsubscribers = collections.map((collection) =>
    adapter.listen(
      collection,
      (records, fromCache) => {
        if (!active()) return;
        // An empty in-memory Firestore cache during offline startup is not
        // evidence of remote deletion. Keep the durable browser cache intact.
        if (fromCache) {
          report();
          return;
        }
        serverSnapshots.add(collection);
        applyRemoteRecords(uid, collection, records);
        report();
      },
      () => {
        listenerFailed = true;
        report();
      },
    ),
  );
  const unsubscribeStorage = subscribeStorage(() => {
    report();
    void flush();
  });
  const retry = setInterval(() => {
    void flush();
  }, 15000);
  report();
  void flush();
  return () => {
    stopped = true;
    clearInterval(retry);
    unsubscribeStorage();
    unsubscribers.forEach((unsubscribe) => unsubscribe());
  };
}
