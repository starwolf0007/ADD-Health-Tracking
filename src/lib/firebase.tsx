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
import { useState, useEffect, createContext, useContext } from 'react';
import firebaseConfig from '../../firebase-applet-config.json';
import { setStorageUser, type SyncRecord } from './storage';
import { startAccountSync, type SyncStatus } from './sync';

const app = getApps().length > 0 ? getApp() : initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app, firebaseConfig.firestoreDatabaseId);

interface AuthContextType {
  user: User | null;
  loading: boolean;
  signInWithGoogle: () => Promise<void>;
  signInAsGuest: () => Promise<void>;
  signOut: () => Promise<void>;
  syncStatus: SyncStatus;
  authError: string | null;
}
const AuthContext = createContext<AuthContextType>({
  user: null,
  loading: true,
  signInWithGoogle: async () => {},
  signInAsGuest: async () => {},
  signOut: async () => {},
  syncStatus: 'idle',
  authError: null,
});

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [syncStatus, setSyncStatus] = useState<SyncStatus>('idle');
  const [authError, setAuthError] = useState<string | null>(null);
  useEffect(
    () =>
      onAuthStateChanged(
        auth,
        (currentUser) => {
          setStorageUser(currentUser?.uid ?? null);
          setSyncStatus(currentUser ? 'syncing' : 'idle');
          setUser(currentUser);
          setLoading(false);
        },
        () => {
          setAuthError('Could not restore sign-in. Local mode is available.');
          setStorageUser(null);
          setUser(null);
          setLoading(false);
        },
      ),
    [],
  );

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
            },
            fail,
          ),
        write: (name, id, value) =>
          setDoc(
            doc(db, 'users', uid, name, id),
            value ? JSON.parse(JSON.stringify(value)) : { _deleted: true },
          ),
      },
      setSyncStatus,
    );
  }, [user?.uid]);

  const runAuth = async (operation: () => Promise<unknown>) => {
    setAuthError(null);
    try {
      await operation();
    } catch {
      setAuthError(
        'Sign-in change failed. Please try again; your account has not been replaced with a guest.',
      );
    }
  };
  const signInWithGoogle = () =>
    runAuth(() => {
      const provider = new GoogleAuthProvider();
      provider.setCustomParameters({ prompt: 'select_account' });
      return signInWithPopup(auth, provider);
    });
  const signInAsGuest = () => runAuth(() => signInAnonymously(auth));
  const signOut = () => runAuth(() => fbSignOut(auth));
  return (
    <AuthContext.Provider
      value={{
        user,
        loading,
        signInWithGoogle,
        signInAsGuest,
        signOut,
        syncStatus,
        authError,
      }}
    >
      {loading ? <p role="status">Restoring account…</p> : children}
    </AuthContext.Provider>
  );
};
export const useFirebaseAuth = () => useContext(AuthContext);
