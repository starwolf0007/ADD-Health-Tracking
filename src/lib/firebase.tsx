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
  collection,
  onSnapshot,
  query,
} from 'firebase/firestore';
import { useState, useEffect, createContext, useContext } from 'react';
import firebaseConfig from '../../firebase-applet-config.json';
import { taskStorage, routineStorage, habitStorage, moodStorage, noteStorage } from './storage';
import { Task, Routine, Habit, MoodLog, Note } from '../types';

// Initialize Firebase App singleton
const app = getApps().length > 0 ? getApp() : initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app, firebaseConfig.firestoreDatabaseId);

interface AuthContextType {
  user: User | null;
  loading: boolean;
  signInWithGoogle: () => Promise<void>;
  signInAsGuest: () => Promise<void>;
  signOut: () => Promise<void>;
  syncStatus: 'idle' | 'syncing' | 'synced' | 'error';
}

const AuthContext = createContext<AuthContextType>({
  user: null,
  loading: true,
  signInWithGoogle: async () => {},
  signInAsGuest: async () => {},
  signOut: async () => {},
  syncStatus: 'idle',
});

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [syncStatus, setSyncStatus] = useState<'idle' | 'syncing' | 'synced' | 'error'>('idle');

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (currentUser) => {
      setUser(currentUser);
      setLoading(false);

      if (currentUser) {
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
          setSyncStatus('synced');
        } catch (err) {
          console.error('Failed to sync user document to Firestore:', err);
          setSyncStatus('error');
        }
      } else {
        setSyncStatus('idle');
      }
    });

    return () => unsubscribe();
  }, []);

  const signInWithGoogle = async () => {
    try {
      const provider = new GoogleAuthProvider();
      provider.setCustomParameters({ prompt: 'select_account' });
      await signInWithPopup(auth, provider);
    } catch (err: any) {
      console.warn('Google popup sign in issue, trying guest sign-in fallback:', err);
      // Fallback to anonymous auth if popup is blocked
      await signInAnonymously(auth);
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
    } catch (err) {
      console.error('Sign out error:', err);
    }
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        loading,
        signInWithGoogle,
        signInAsGuest,
        signOut,
        syncStatus,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useFirebaseAuth = () => useContext(AuthContext);

// ---------------------------------------------------------------------------
// Firestore Real-time Persistence Helper
// ---------------------------------------------------------------------------
export function useFirestoreSync(user: User | null) {
  useEffect(() => {
    if (!user) return;

    // 1. Sync tasks from Firestore
    const tasksRef = collection(db, 'users', user.uid, 'tasks');
    const unsubTasks = onSnapshot(query(tasksRef), (snapshot) => {
      snapshot.docChanges().forEach((change) => {
        if (change.type === 'added' || change.type === 'modified') {
          const data = change.doc.data() as Task;
          taskStorage.save(data);
        } else if (change.type === 'removed') {
          taskStorage.delete(change.doc.id);
        }
      });
    });

    // 2. Sync notes from Firestore
    const notesRef = collection(db, 'users', user.uid, 'notes');
    const unsubNotes = onSnapshot(query(notesRef), (snapshot) => {
      snapshot.docChanges().forEach((change) => {
        if (change.type === 'added' || change.type === 'modified') {
          const data = change.doc.data() as Note;
          noteStorage.save(data);
        } else if (change.type === 'removed') {
          noteStorage.delete(change.doc.id);
        }
      });
    });

    return () => {
      unsubTasks();
      unsubNotes();
    };
  }, [user]);

  // Push local task to Firestore
  const syncTaskToFirestore = async (task: Task) => {
    if (!user) return;
    try {
      const taskDoc = doc(db, 'users', user.uid, 'tasks', task.id);
      await setDoc(taskDoc, task, { merge: true });
    } catch (err) {
      console.error('Error syncing task to Firestore:', err);
    }
  };

  // Push local note to Firestore
  const syncNoteToFirestore = async (note: Note) => {
    if (!user) return;
    try {
      const noteDoc = doc(db, 'users', user.uid, 'notes', note.id);
      await setDoc(noteDoc, note, { merge: true });
    } catch (err) {
      console.error('Error syncing note to Firestore:', err);
    }
  };

  return { syncTaskToFirestore, syncNoteToFirestore };
}
