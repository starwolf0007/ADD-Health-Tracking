import { initializeApp, getApps, getApp } from 'firebase/app';
import {
  getAuth,
  GoogleAuthProvider,
  signInWithPopup,
  signInAnonymously,
  signOut as fbSignOut,
  onAuthStateChanged,
  User,
} from 'firebase/auth';
import {
  getFirestore,
  doc,
  setDoc,
  deleteDoc,
  collection,
  onSnapshot,
  query,
} from 'firebase/firestore';
import { useState, useEffect, createContext, useContext, useCallback } from 'react';
import firebaseConfig from '../../firebase-applet-config.json';
import {
  taskStorage,
  noteStorage,
  setStorageScope,
  offlineQueueStorage,
  registerMutationListener,
  StorageMutation,
} from './storage';
import {
  GOOGLE_DRIVE_FILE_SCOPE,
  verifyDriveFileScope,
  registerDriveTokenHandlers,
  calculateBackoffDelay,
  googleDriveService,
  setDriveBackupScope,
  DriveBackupHealthState,
} from './googleDrive';
import { Task, Note } from '../types';

// Least-privilege Google Drive scope for visible user backup files
export const GOOGLE_DRIVE_SCOPES: readonly string[] = [
  GOOGLE_DRIVE_FILE_SCOPE,
];

if (!verifyDriveFileScope(GOOGLE_DRIVE_SCOPES)) {
  throw new Error(
    `Invalid GOOGLE_DRIVE_SCOPES configuration: must strictly use "${GOOGLE_DRIVE_FILE_SCOPE}".`
  );
}

// Initialize Firebase App singleton
const app = getApps().length > 0 ? getApp() : initializeApp(firebaseConfig);
export const auth = getAuth(app);
const FIRESTORE_DB_ID =
  (firebaseConfig as any).firestoreDatabaseId ||
  'ai-studio-addhealthtrackin-2d42f09e-2429-4958-8bf3-d2ee7b9ac637';
export const db = getFirestore(app, FIRESTORE_DB_ID);

// In-memory token cache (NEVER stored in localStorage or sessionStorage)
let inMemoryAccessToken: string | null = null;

export const getCachedAccessToken = (): string | null => inMemoryAccessToken;

export type SyncStatus = 'synced' | 'syncing' | 'queued' | 'offline' | 'error';

interface AuthContextType {
  user: User | null;
  accessToken: string | null;
  loading: boolean;
  signInWithGoogle: () => Promise<string | null>;
  signInAsGuest: () => Promise<void>;
  signOut: () => Promise<void>;
  syncStatus: SyncStatus;
  pendingQueueCount: number;
  lastSyncedAt: string | null;
  syncError: string | null;
  triggerManualSync: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType>({
  user: null,
  accessToken: null,
  loading: true,
  signInWithGoogle: async () => null,
  signInAsGuest: async () => {},
  signOut: async () => {},
  syncStatus: 'synced',
  pendingQueueCount: 0,
  lastSyncedAt: null,
  syncError: null,
  triggerManualSync: async () => {},
});

// Helper to flush queued operations with exponential backoff retry for transient drops
export async function flushOfflineQueueForUser(
  currentUser: User,
  maxRetriesPerItem = 3
): Promise<number> {
  const queue = offlineQueueStorage.getQueue(currentUser.uid);
  if (queue.length === 0) return 0;

  console.info(
    `[FirestoreSync] Flushing ${queue.length} queued offline operation(s) for uid=${currentUser.uid.slice(0, 8)}...`
  );

  let processed = 0;
  for (const op of queue) {
    let opSucceeded = false;
    for (let attempt = 1; attempt <= maxRetriesPerItem; attempt++) {
      try {
        if (op.type === 'task' && op.data) {
          const taskDoc = doc(db, 'users', currentUser.uid, 'tasks', op.entityId);
          await setDoc(taskDoc, op.data, { merge: true });
          offlineQueueStorage.dequeue(op.id, currentUser.uid);
          processed++;
        } else if (op.type === 'delete_task') {
          const taskDoc = doc(db, 'users', currentUser.uid, 'tasks', op.entityId);
          await deleteDoc(taskDoc);
          offlineQueueStorage.dequeue(op.id, currentUser.uid);
          processed++;
        } else if (op.type === 'note' && op.data) {
          const noteDoc = doc(db, 'users', currentUser.uid, 'notes', op.entityId);
          await setDoc(noteDoc, op.data, { merge: true });
          offlineQueueStorage.dequeue(op.id, currentUser.uid);
          processed++;
        } else if (op.type === 'delete_note') {
          const noteDoc = doc(db, 'users', currentUser.uid, 'notes', op.entityId);
          await deleteDoc(noteDoc);
          offlineQueueStorage.dequeue(op.id, currentUser.uid);
          processed++;
        }
        opSucceeded = true;
        break;
      } catch (err) {
        if (attempt < maxRetriesPerItem && (typeof navigator === 'undefined' || navigator.onLine)) {
          const delayMs = calculateBackoffDelay(attempt, 500, 4000);
          console.warn(
            `[FirestoreSync] Transient failure flushing queued item ${op.id} (attempt ${attempt}/${maxRetriesPerItem}). Retrying in ${delayMs}ms...`,
            err
          );
          await new Promise((resolve) => setTimeout(resolve, delayMs));
        } else {
          console.warn(
            `[FirestoreSync] Failed to process queued offline item ${op.id} after ${attempt} attempt(s):`,
            err
          );
        }
      }
    }

    if (!opSucceeded) {
      // Stop flushing remaining items until next online/manual retry
      break;
    }
  }

  console.info(
    `[FirestoreSync] Flushed ${processed}/${queue.length} queued operation(s).`
  );
  return processed;
}

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [accessToken, setAccessToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [isOnline, setIsOnline] = useState(
    typeof navigator !== 'undefined' ? navigator.onLine : true
  );
  const [syncStatus, setSyncStatus] = useState<SyncStatus>('synced');
  const [pendingQueueCount, setPendingQueueCount] = useState<number>(0);
  const [lastSyncedAt, setLastSyncedAt] = useState<string | null>(null);
  const [syncError, setSyncError] = useState<string | null>(null);

  // Register OAuth token expiration callback so Drive 401 errors clear stale in-memory tokens
  useEffect(() => {
    registerDriveTokenHandlers({
      onTokenExpired: (reason: string) => {
        console.warn(`[DriveSync] Clearing expired in-memory OAuth token: ${reason}`);
        inMemoryAccessToken = null;
        setAccessToken(null);
        setSyncError(reason);
      },
    });
    return () => {
      registerDriveTokenHandlers({});
    };
  }, []);

  // Monitor online / offline network events
  useEffect(() => {
    const handleOnline = () => {
      console.info('[Sync] Network connection restored. Triggering sync check...');
      setIsOnline(true);
      if (user) {
        triggerManualSync();
      }
    };
    const handleOffline = () => {
      console.warn('[Sync] Network connection lost. Switching to offline queue mode.');
      setIsOnline(false);
      setSyncStatus('offline');
    };

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, [user]);

  // Update pending queue count whenever user changes or storage updates
  const updateQueueCount = useCallback((uid?: string) => {
    const targetUid = uid || user?.uid;
    if (!targetUid) {
      setPendingQueueCount(0);
      return;
    }
    const q = offlineQueueStorage.getQueue(targetUid);
    setPendingQueueCount(q.length);
    if (!navigator.onLine) {
      setSyncStatus('offline');
    } else if (q.length > 0) {
      setSyncStatus('queued');
    } else {
      setSyncStatus('synced');
    }
  }, [user]);

  const triggerManualSync = useCallback(async () => {
    if (!user) return;
    if (!navigator.onLine) {
      setSyncStatus('offline');
      return;
    }

    setSyncStatus('syncing');
    setSyncError(null);
    try {
      await flushOfflineQueueForUser(user);
      const remaining = offlineQueueStorage.getQueue(user.uid).length;
      setPendingQueueCount(remaining);
      if (remaining === 0) {
        const nowIso = new Date().toISOString();
        setLastSyncedAt(nowIso);
        setSyncStatus('synced');
      } else {
        setSyncStatus('queued');
      }
    } catch (err: any) {
      const msg = err?.message || 'Failed to synchronize offline queue';
      console.error('[FirestoreSync] Manual sync error:', msg);
      setSyncError(msg);
      setSyncStatus('error');
    }
  }, [user]);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (currentUser) => {
      setUser(currentUser);
      setLoading(false);

      if (!currentUser) {
        // Clear cached token in memory on sign out and switch scope to guest
        inMemoryAccessToken = null;
        setAccessToken(null);
        setStorageScope('guest');
        setDriveBackupScope('guest');
        setSyncStatus('synced');
        setPendingQueueCount(0);
        setSyncError(null);
        return;
      }

      // Switch active storage scope to signed-in user UID
      setStorageScope(currentUser.uid);
      setDriveBackupScope(currentUser.uid);
      updateQueueCount(currentUser.uid);

      // Save/update user profile document in Firestore
      try {
        const userRef = doc(db, 'users', currentUser.uid);
        await setDoc(
          userRef,
          {
            displayName: currentUser.displayName || 'Friend',
            email: currentUser.email || '',
            photoURL: currentUser.photoURL || '',
            updatedAt: new Date().toISOString(),
          },
          { merge: true }
        );

        // Attempt to flush any offline operations queued for this user
        if (navigator.onLine) {
          await flushOfflineQueueForUser(currentUser);
          updateQueueCount(currentUser.uid);
          setLastSyncedAt(new Date().toISOString());
          setSyncError(null);
        }
      } catch (err: any) {
        console.error('Failed to sync user document to Firestore:', err);
        setSyncError(err?.message || 'Failed to sync user profile');
        setSyncStatus('error');
      }
    });

    return () => unsubscribe();
  }, [updateQueueCount]);

  const signInWithGoogle = async (): Promise<string | null> => {
    try {
      if (!verifyDriveFileScope(GOOGLE_DRIVE_SCOPES)) {
        throw new Error('Drive scope verification failed: only drive.file is permitted.');
      }

      const provider = new GoogleAuthProvider();
      // Add least-privilege Drive scopes to provider
      GOOGLE_DRIVE_SCOPES.forEach((scope) => provider.addScope(scope));
      provider.setCustomParameters({ prompt: 'select_account' });

      console.info(
        `[DriveSync] Requesting Google OAuth sign-in with least-privilege scope: ${GOOGLE_DRIVE_SCOPES.join(', ')}`
      );

      const result = await signInWithPopup(auth, provider);
      const credential = GoogleAuthProvider.credentialFromResult(result);

      if (credential?.accessToken) {
        inMemoryAccessToken = credential.accessToken;
        setAccessToken(credential.accessToken);
        setSyncError(null);
        googleDriveService.clearSyncError();
        console.info('[DriveSync] Google OAuth token acquired in memory (drive.file authorized).');
        return credential.accessToken;
      }
      return null;
    } catch (err: any) {
      console.warn('Google popup sign in issue, trying guest sign-in fallback:', err);
      try {
        await signInAnonymously(auth);
      } catch {}
      return null;
    }
  };

  const signInAsGuest = async () => {
    try {
      await signInAnonymously(auth);
    } catch (err) {
      console.error('Anonymous sign-in error:', err);
    }
  };

  const signOut = async () => {
    try {
      await fbSignOut(auth);
      inMemoryAccessToken = null;
      setAccessToken(null);
      setSyncError(null);
      setStorageScope('guest');
      setDriveBackupScope('guest');
      console.info('[DriveSync] Signed out and cleared in-memory OAuth credentials.');
    } catch (err) {
      console.error('Sign out error:', err);
    }
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        accessToken,
        loading,
        signInWithGoogle,
        signInAsGuest,
        signOut,
        syncStatus: !isOnline ? 'offline' : syncStatus,
        pendingQueueCount,
        lastSyncedAt,
        syncError,
        triggerManualSync,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useFirebaseAuth = () => useContext(AuthContext);

export function useDriveBackupHealth(): DriveBackupHealthState {
  const [health, setHealth] = useState<DriveBackupHealthState>(() =>
    googleDriveService.getBackupHealth()
  );

  useEffect(() => {
    setHealth(googleDriveService.getBackupHealth());
    return googleDriveService.subscribeBackupHealth((nextState) => {
      setHealth(nextState);
    });
  }, []);

  return health;
}

// ---------------------------------------------------------------------------
// Firestore Real-time Persistence & Offline-Resilient Synchronization
// ---------------------------------------------------------------------------
export function useFirestoreSync(user: User | null) {
  const { triggerManualSync } = useFirebaseAuth();

  // 1. Subscribe to real-time Firestore changes for user
  useEffect(() => {
    if (!user) return;

    // A. Sync tasks from Firestore
    const tasksRef = collection(db, 'users', user.uid, 'tasks');
    const unsubTasks = onSnapshot(
      query(tasksRef),
      (snapshot) => {
        snapshot.docChanges().forEach((change) => {
          if (change.type === 'added' || change.type === 'modified') {
            const data = change.doc.data() as Task;
            // Pass isRemote = true to prevent echo loop
            taskStorage.save(data, true, user.uid);
          } else if (change.type === 'removed') {
            taskStorage.delete(change.doc.id, true, user.uid);
          }
        });
      },
      (err) => {
        console.warn('Tasks onSnapshot subscription error:', err);
      }
    );

    // B. Sync notes from Firestore
    const notesRef = collection(db, 'users', user.uid, 'notes');
    const unsubNotes = onSnapshot(
      query(notesRef),
      (snapshot) => {
        snapshot.docChanges().forEach((change) => {
          if (change.type === 'added' || change.type === 'modified') {
            const data = change.doc.data() as Note;
            // Pass isRemote = true to prevent echo loop
            noteStorage.save(data, true, user.uid);
          } else if (change.type === 'removed') {
            noteStorage.delete(change.doc.id, true, user.uid);
          }
        });
      },
      (err) => {
        console.warn('Notes onSnapshot subscription error:', err);
      }
    );

    return () => {
      unsubTasks();
      unsubNotes();
    };
  }, [user]);

  // 2. Intercept local storage mutations and push to Firestore or enqueue offline
  useEffect(() => {
    if (!user) return;

    const unregister = registerMutationListener(async (mutation: StorageMutation) => {
      if (!navigator.onLine) {
        // Enqueue immediately if browser is offline
        if (mutation.type === 'task_saved') {
          offlineQueueStorage.enqueue(
            { type: 'task', entityId: mutation.task.id, data: mutation.task },
            user.uid
          );
        } else if (mutation.type === 'task_deleted') {
          offlineQueueStorage.enqueue(
            { type: 'delete_task', entityId: mutation.taskId },
            user.uid
          );
        } else if (mutation.type === 'note_saved') {
          offlineQueueStorage.enqueue(
            { type: 'note', entityId: mutation.note.id, data: mutation.note },
            user.uid
          );
        } else if (mutation.type === 'note_deleted') {
          offlineQueueStorage.enqueue(
            { type: 'delete_note', entityId: mutation.noteId },
            user.uid
          );
        }
        return;
      }

      // Online: attempt immediate Firestore write
      try {
        if (mutation.type === 'task_saved') {
          const taskDoc = doc(db, 'users', user.uid, 'tasks', mutation.task.id);
          await setDoc(taskDoc, mutation.task, { merge: true });
        } else if (mutation.type === 'task_deleted') {
          const taskDoc = doc(db, 'users', user.uid, 'tasks', mutation.taskId);
          await deleteDoc(taskDoc);
        } else if (mutation.type === 'note_saved') {
          const noteDoc = doc(db, 'users', user.uid, 'notes', mutation.note.id);
          await setDoc(noteDoc, mutation.note, { merge: true });
        } else if (mutation.type === 'note_deleted') {
          const noteDoc = doc(db, 'users', user.uid, 'notes', mutation.noteId);
          await deleteDoc(noteDoc);
        }
      } catch (err) {
        console.warn('Firestore write failed, enqueuing to offline queue:', err);
        if (mutation.type === 'task_saved') {
          offlineQueueStorage.enqueue(
            { type: 'task', entityId: mutation.task.id, data: mutation.task },
            user.uid
          );
        } else if (mutation.type === 'task_deleted') {
          offlineQueueStorage.enqueue(
            { type: 'delete_task', entityId: mutation.taskId },
            user.uid
          );
        } else if (mutation.type === 'note_saved') {
          offlineQueueStorage.enqueue(
            { type: 'note', entityId: mutation.note.id, data: mutation.note },
            user.uid
          );
        } else if (mutation.type === 'note_deleted') {
          offlineQueueStorage.enqueue(
            { type: 'delete_note', entityId: mutation.noteId },
            user.uid
          );
        }
      }
    });

    return () => unregister();
  }, [user]);

  // Push local task to Firestore explicitly (manual trigger)
  const syncTaskToFirestore = async (task: Task) => {
    if (!user) return;
    try {
      const taskDoc = doc(db, 'users', user.uid, 'tasks', task.id);
      await setDoc(taskDoc, task, { merge: true });
    } catch {
      offlineQueueStorage.enqueue(
        { type: 'task', entityId: task.id, data: task },
        user.uid
      );
    }
  };

  // Push local note to Firestore explicitly (manual trigger)
  const syncNoteToFirestore = async (note: Note) => {
    if (!user) return;
    try {
      const noteDoc = doc(db, 'users', user.uid, 'notes', note.id);
      await setDoc(noteDoc, note, { merge: true });
    } catch {
      offlineQueueStorage.enqueue(
        { type: 'note', entityId: note.id, data: note },
        user.uid
      );
    }
  };

  return { syncTaskToFirestore, syncNoteToFirestore, triggerManualSync };
}
