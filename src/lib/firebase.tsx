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
import { Task, Note } from '../types';

// Least-privilege Google Drive scope for visible user backup files
export const GOOGLE_DRIVE_SCOPES = [
  'https://www.googleapis.com/auth/drive.file',
];

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
  triggerManualSync: async () => {},
});

// Helper to flush queued operations
export async function flushOfflineQueueForUser(currentUser: User): Promise<number> {
  const queue = offlineQueueStorage.getQueue(currentUser.uid);
  if (queue.length === 0) return 0;

  let processed = 0;
  for (const op of queue) {
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
    } catch (err) {
      console.warn(`Failed to process queued offline item ${op.id}:`, err);
      // Stop flushing if network failure occurs
      break;
    }
  }
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

  // Monitor online / offline network events
  useEffect(() => {
    const handleOnline = () => {
      setIsOnline(true);
      if (user) {
        triggerManualSync();
      }
    };
    const handleOffline = () => {
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
    try {
      await flushOfflineQueueForUser(user);
      const remaining = offlineQueueStorage.getQueue(user.uid).length;
      setPendingQueueCount(remaining);
      setSyncStatus(remaining > 0 ? 'queued' : 'synced');
    } catch {
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
        setSyncStatus('synced');
        setPendingQueueCount(0);
        return;
      }

      // Switch active storage scope to signed-in user UID
      setStorageScope(currentUser.uid);
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
        }
      } catch (err) {
        console.error('Failed to sync user document to Firestore:', err);
        setSyncStatus('error');
      }
    });

    return () => unsubscribe();
  }, [updateQueueCount]);

  const signInWithGoogle = async (): Promise<string | null> => {
    try {
      const provider = new GoogleAuthProvider();
      // Add least-privilege Drive scopes to provider
      GOOGLE_DRIVE_SCOPES.forEach((scope) => provider.addScope(scope));
      provider.setCustomParameters({ prompt: 'select_account' });

      const result = await signInWithPopup(auth, provider);
      const credential = GoogleAuthProvider.credentialFromResult(result);

      if (credential?.accessToken) {
        inMemoryAccessToken = credential.accessToken;
        setAccessToken(credential.accessToken);
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
      setStorageScope('guest');
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
        triggerManualSync,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useFirebaseAuth = () => useContext(AuthContext);

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
