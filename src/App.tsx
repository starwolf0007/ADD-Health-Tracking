import React from 'react';
import { useFirebaseAuth } from './lib/firebase';
import { AppShell } from './components/AppShell';

export const App: React.FC = () => {
  const { user } = useFirebaseAuth();
  return <AppShell key={user?.uid ?? 'local'} />;
};

export default App;
