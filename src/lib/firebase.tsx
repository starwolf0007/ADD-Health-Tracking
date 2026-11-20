import { initializeApp, getApps, getApp } from 'firebase/app';
import {
  getAuth,
  GoogleAuthProvider,
  signInWithPopup,
  signInAnonymously,
  signOut as fbSignOut,
  onAuthStateChanged,
  type User,
} from 'firebase/auth';
import {
  getFirestore,
  doc,
  setDoc,
  collection,
  onSnapshot,
} from 'firebase/firestore';
import { useState, useEffect, createContext, useContext, useCallback } from 'react';
import firebaseConfig from '../../firebase-applet-config.json';
import {
  setStorageUser,
  setStorageScope,
  offlineQueueStorage,
  type SyncRecord,
} from './storage';
import { startAccountSync, type SyncStatus as AccountSyncStatus } from './sync';
import {
  GOOGLE_DRIVE_FILE_SCOPE,
  verifyDriveFileScope,
  googleDriveService,
  setDriveBackupScope,
  type DriveBackupHealthState,
} from './googleDrive';
import type { Task, Note } from '../types';

export const GOOGLE_DRIVE_SCOPES: readonly string[] = [
  GOOGLE_DRIVE_FILE_SCOPE,
];

if (!verifyDriveFileScope(GOOGLE_DRIVE_SCOPES)) {
  throw new Error(
    `Invalid GOOGLE_DRIVE_SCOPES configuration: must strictly use "${GOOGLE_DRIVE_FILE_SCOPE}".`
  );
}

const app = getApps().length > 0 ? getApp() : initializeApp(firebaseConfig);
export const auth = getAuth(app);
const FIRESTORE_DB_ID =
  (firebaseConfig as any).firestoreDatabaseId ||
  'ai-studio-addhealthtrackin-2d42f09e-2429-4958-8bf3-d2ee7b9ac637';
export const db = getFirestore(app, FIRESTORE_DB_ID);

// In-memory token cache (NEVER stored in localStorage or sessionStorage)
let inMemoryAccessToken: string | null = null;
export const getCachedAccessToken = (): string | null => inMemoryAccessToken;

export type SyncStatus = 'idle' | 'syncing' | 'synced' | 'queued' | 'offline' | 'error';

interface AuthContextType {
  user: User | null;
  accessToken: string | null;
  loading: boolean;
  signInWithGoogle: () => Promise<string | null>;
  signInAsGuest: () => Promise<void>;
  signOut: () => Promise<void>;
  syncStatus: SyncStatus;
  authError: string | null;
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
  syncStatus: 'idle',
  authError: null,
  pendingQueueCount: 0,
  lastSyncedAt: null,
  syncError: null,
  triggerManualSync: async () => {},
});

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  const [user, setUser] = useState<User | null>(null);
  const [accessToken, setAccessToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [syncStatus, setSyncStatus] = useState<SyncStatus>('idle');
  const [authError, setAuthError] = useState<string | null>(null);
  const [lastSyncedAt, setLastSyncedAt] = useState<string | null>(null);
  const [pendingQueueCount, setPendingQueueCount] = useState<number>(0);

  const updateQueueCount = useCallback((uid?: string | null) => {
    const queue = offlineQueueStorage.getQueue(uid || undefined);
    setPendingQueueCount(queue.length);
  }, []);

  useEffect(() => {
    return onAuthStateChanged(
      auth,
      async (currentUser) => {
        if (!currentUser) {
          inMemoryAccessToken = null;
          setAccessToken(null);
          setStorageUser(null);
          setDriveBackupScope('guest');
          setUser(null);
          setSyncStatus('idle');
          setPendingQueueCount(0);
          setLoading(false);
          return;
        }

        setStorageUser(currentUser.uid);
        setDriveBackupScope(currentUser.uid);
        setUser(currentUser);
        setSyncStatus('syncing');
        updateQueueCount(currentUser.uid);
        setLoading(false);

        // Update profile in Firestore non-blockingly
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
            { merge: true },
          );
        } catch (err) {
          console.warn('Profile sync notice:', err);
        }
      },
      () => {
        setAuthError('Could not restore sign-in. Local mode is available.');
        setStorageUser(null);
        setDriveBackupScope('guest');
        setUser(null);
        setLoading(false);
      },
    );
  }, [updateQueueCount]);

  // Connect durable account sync engine
  useEffect(() => {
    if (!user) return;
    const uid = user.uid;
    return startAccountSync(
      uid,
      {
        listen: (name, receive, fail) =>
          onSnapshot(
            collection(db, 'users', uid, name),
            { includeMetadataChanges: true },
            (snapshot) => {
              const records = snapshot.docs
                .filter((item) => !item.data()._deleted)
                .map((item) => ({ ...item.data(), id: item.id }) as SyncRecord);
              receive(
                records,
                snapshot.metadata.fromCache ||
                  snapshot.metadata.hasPendingWrites,
              );
              updateQueueCount(uid);
              setLastSyncedAt(new Date().toISOString());
            },
            fail,
          ),
        write: async (name, id, value) => {
          await setDoc(
            doc(db, 'users', uid, name, id),
            value ? JSON.parse(JSON.stringify(value)) : { _deleted: true },
          );
          updateQueueCount(uid);
          setLastSyncedAt(new Date().toISOString());
        },
      },
      (status: AccountSyncStatus) => {
        setSyncStatus(status);
        updateQueueCount(uid);
      },
    );
  }, [user?.uid, updateQueueCount]);

  const runAuth = async <T,>(operation: () => Promise<T>): Promise<T | null> => {
    setAuthError(null);
    try {
      return await operation();
    } catch (err: any) {
      console.warn('Authentication error:', err);
      setAuthError(
        'Sign-in change failed. Please try again; your account has not been replaced with a guest.',
      );
      return null;
    }
  };

  const signInWithGoogle = async (): Promise<string | null> => {
    return runAuth(async () => {
      const provider = new GoogleAuthProvider();
      GOOGLE_DRIVE_SCOPES.forEach((scope) => provider.addScope(scope));
      provider.setCustomParameters({ prompt: 'select_account' });
      const result = await signInWithPopup(auth, provider);
      const credential = GoogleAuthProvider.credentialFromResult(result);
      if (credential?.accessToken) {
        inMemoryAccessToken = credential.accessToken;
        setAccessToken(credential.accessToken);
        googleDriveService.clearSyncError();
        return credential.accessToken;
      }
      return null;
    });
  };

  const signInAsGuest = async () => {
    await runAuth(() => signInAnonymously(auth));
  };

  const signOut = async () => {
    await runAuth(async () => {
      inMemoryAccessToken = null;
      setAccessToken(null);
      await fbSignOut(auth);
      setStorageUser(null);
      setDriveBackupScope('guest');
    });
  };

  const triggerManualSync = async () => {
    if (user) {
      updateQueueCount(user.uid);
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
        syncStatus,
        authError,
        pendingQueueCount,
        lastSyncedAt,
        syncError: authError,
        triggerManualSync,
      }}
    >
      {loading ? <p role="status">Restoring account…</p> : children}
    </AuthContext.Provider>
  );
};

export const useFirebaseAuth = () => useContext(AuthContext);

export function useDriveBackupHealth(): DriveBackupHealthState {
  const [health, setHealth] = useState<DriveBackupHealthState>(() =>
    googleDriveService.getBackupHealth(),
  );

  useEffect(() => {
    setHealth(googleDriveService.getBackupHealth());
    return googleDriveService.subscribeBackupHealth((nextState) => {
      setHealth(nextState);
    });
  }, []);

  return health;
}

// Backward-compatible hook for AppShell
export function useFirestoreSync(_user: User | null) {
  const { triggerManualSync } = useFirebaseAuth();
  return { triggerManualSync };
}
