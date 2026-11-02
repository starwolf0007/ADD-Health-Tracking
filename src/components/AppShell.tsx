import React, { useState, useEffect } from 'react';
import {
  Sun,
  StickyNote,
  Repeat,
  Settings,
  Plus,
  Flower2,
  LogIn,
  LogOut,
  Cloud,
  Radio,
  Sparkles,
  Clock,
  HardDrive,
  User as UserIcon,
  CloudOff,
  RefreshCw,
  AlertCircle,
} from 'lucide-react';
import { Routine, Achievement, Task } from '../types';
import {
  useNeuroStorage,
  exportAllData,
} from '../lib/storage';
import { useFirebaseAuth, useFirestoreSync } from '../lib/firebase';
import { googleDriveService } from '../lib/googleDrive';
import { TodayScreen } from '../screens/TodayScreen';
import { NotesScreen } from '../screens/NotesScreen';
import { RoutinesListScreen } from '../screens/RoutinesListScreen';
import { ReflectScreen } from '../screens/ReflectScreen';
import { RoutineRunScreen } from '../screens/RoutineRunScreen';
import { SettingsScreen } from '../screens/SettingsScreen';
import { ConnectedServicesScreen } from '../screens/ConnectedServicesScreen';
import { HealthIntegrationsScreen } from '../screens/HealthIntegrationsScreen';
import { GoogleDriveScreen } from '../screens/GoogleDriveScreen';
import { LexiChatInterface } from './LexiChatInterface';
import { LiveVoiceScreen } from '../screens/LiveVoiceScreen';
import { VisualClockTimer } from './VisualClockTimer';
import { CaptureSheet } from './CaptureSheet';
import { AchievementToast } from './AchievementToast';

export const AppShell: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'today' | 'routines' | 'lexi' | 'notes' | 'reflect'>('today');
  const [activeOverlay, setActiveOverlay] = useState<
    'settings' | 'connected_services' | 'health_integrations' | 'live_voice' | 'google_drive' | null
  >(null);
  const [runningRoutine, setRunningRoutine] = useState<Routine | null>(null);
  const [isCaptureOpen, setIsCaptureOpen] = useState(false);
  const [currentAchievement, setCurrentAchievement] = useState<Achievement | null>(null);

  // Visual Clock Timer State (5m, 25m, 50m pomodoro)
  const [visualTimerState, setVisualTimerState] = useState<{
    isOpen: boolean;
    task: Task | null;
    initialMinutes: number;
  }>({
    isOpen: false,
    task: null,
    initialMinutes: 25,
  });

  const storage = useNeuroStorage();
  const {
    user,
    accessToken,
    signInWithGoogle,
    signOut,
    syncStatus,
    pendingQueueCount,
    triggerManualSync,
  } = useFirebaseAuth();

  // Activate Firestore real-time synchronization
  useFirestoreSync(user);

  // Automatic Google Drive Daily Backup
  useEffect(() => {
    if (!accessToken || !storage.settings.autoDriveBackup) return;

    const payload = exportAllData({ includeSensitive: false });
    googleDriveService.checkAndRunAutoBackup(accessToken, payload).then((res) => {
      if (res.executed) {
        setCurrentAchievement({
          id: `backup-${Date.now()}`,
          title: 'GOOGLE DRIVE SYNCED',
          message: `Automatic daily snapshot created (${res.fileName})`,
          type: 'backup',
          timestamp: Date.now(),
        });
      }
    }).catch((err) => {
      console.warn('Auto backup check encountered error:', err);
    });
  }, [accessToken, storage.settings.autoDriveBackup]);

  const greetingName = user?.displayName || storage.settings.displayName;

  return (
    <div className="min-h-screen bg-[#0C0C0D] text-[#F0F0F0] flex flex-col selection:bg-[#2FB083]/30">
      {/* Achievement Toast Host */}
      <AchievementToast
        achievement={currentAchievement}
        onDismiss={() => setCurrentAchievement(null)}
      />

      {/* Top Header */}
      <header className="sticky top-0 z-30 bg-[#0C0C0D]/90 backdrop-blur-md border-b border-[#232326] px-4 py-2.5 flex items-center justify-between max-w-2xl mx-auto w-full">
        <div className="flex items-center gap-2.5">
          {user?.photoURL ? (
            <img
              src={user.photoURL}
              alt={user.displayName || 'User'}
              className="w-8 h-8 rounded-full border border-[#232326] object-cover"
            />
          ) : (
            <div className="w-8 h-8 rounded-full bg-[#1C1C1F] border border-[#232326] flex items-center justify-center text-[#2FB083]">
              <UserIcon className="w-4 h-4" />
            </div>
          )}
          <div>
            <h1 className="text-sm sm:text-base font-medium text-[#F0F0F0] leading-none">
              {greetingName ? `Hey, ${greetingName}` : 'NeuroFlow'}
            </h1>
            <div className="flex items-center gap-1.5 mt-1">
              {user ? (
                syncStatus === 'synced' ? (
                  <span className="text-[10px] text-[#2FB083] font-mono flex items-center gap-1">
                    <Cloud className="w-2.5 h-2.5" />
                    Firestore Synced
                  </span>
                ) : syncStatus === 'syncing' ? (
                  <span className="text-[10px] text-[#4285F4] font-mono flex items-center gap-1">
                    <RefreshCw className="w-2.5 h-2.5 animate-spin" />
                    Syncing ({pendingQueueCount})
                  </span>
                ) : syncStatus === 'offline' ? (
                  <span className="text-[10px] text-[#8A8A8E] font-mono flex items-center gap-1">
                    <CloudOff className="w-2.5 h-2.5" />
                    Offline ({pendingQueueCount} queued)
                  </span>
                ) : syncStatus === 'queued' ? (
                  <button
                    onClick={triggerManualSync}
                    className="text-[10px] text-[#D9A441] hover:underline font-mono flex items-center gap-1"
                    title="Tap to retry offline sync"
                  >
                    <Clock className="w-2.5 h-2.5" />
                    {pendingQueueCount} queued to sync
                  </button>
                ) : (
                  <button
                    onClick={triggerManualSync}
                    className="text-[10px] text-[#EB5757] hover:underline font-mono flex items-center gap-1"
                    title="Sync issue. Tap to retry."
                  >
                    <AlertCircle className="w-2.5 h-2.5" />
                    Sync issue ({pendingQueueCount})
                  </button>
                )
              ) : (
                <div className="flex items-center gap-2">
                  <span className="text-[10px] text-[#8A8A8E] font-mono">Guest Mode</span>
                  <button
                    onClick={signInWithGoogle}
                    className="text-[10px] text-[#2FB083] hover:underline flex items-center gap-1 transition-colors"
                  >
                    <LogIn className="w-2.5 h-2.5" />
                    Sign in
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {/* Visual Clock Timer Quick Launcher (Pomodoro) */}
          <button
            onClick={() =>
              setVisualTimerState({ isOpen: true, task: null, initialMinutes: 25 })
            }
            className="flex items-center gap-1 px-2.5 py-1.5 rounded-xl bg-[#2FB083]/15 hover:bg-[#2FB083]/25 text-[#2FB083] text-xs font-semibold border border-[#2FB083]/30 transition-all shadow-sm"
            title="Visual Clock Timer (5m, 25m, 50m pomodoro)"
          >
            <Clock className="w-3.5 h-3.5" />
            <span className="hidden sm:inline">Timer</span>
          </button>

          {/* Google Drive Quick Launcher */}
          <button
            onClick={() => setActiveOverlay('google_drive')}
            className="flex items-center gap-1 px-2.5 py-1.5 rounded-xl bg-[#4285F4]/15 hover:bg-[#4285F4]/25 text-[#4285F4] text-xs font-semibold border border-[#4285F4]/30 transition-all shadow-sm"
            title="Google Drive Files & Backups"
          >
            <HardDrive className="w-3.5 h-3.5" />
            <span className="hidden sm:inline">Drive</span>
          </button>

          {/* Live Voice Quick Trigger */}
          <button
            onClick={() => setActiveOverlay('live_voice')}
            className="flex items-center gap-1 px-2.5 py-1.5 rounded-xl bg-[#BB86FC]/15 hover:bg-[#BB86FC]/25 text-[#BB86FC] text-xs font-semibold border border-[#BB86FC]/30 transition-all shadow-sm"
            title="Start real-time voice conversation with gemini-3.8-live"
          >
            <Radio className="w-3.5 h-3.5 animate-pulse" />
            <span className="hidden sm:inline">Voice</span>
          </button>

          <button
            onClick={() => setActiveOverlay('settings')}
            className="p-2 text-[#8A8A8E] hover:text-[#F0F0F0] hover:bg-[#161618] rounded-xl transition-colors"
            title="Settings"
            aria-label="Settings"
          >
            <Settings className="w-5 h-5" />
          </button>
        </div>
      </header>

      {/* Primary Tab View */}
      <main className="flex-1 max-w-2xl mx-auto w-full">
        {activeTab === 'today' && (
          <TodayScreen
            tasks={storage.tasks}
            routines={storage.routines}
            habits={storage.habits}
            todayMood={storage.todayMood}
            onOpenLexi={() => setActiveTab('lexi')}
            onOpenSettings={() => setActiveOverlay('settings')}
            onLaunchRoutine={(routine) => setRunningRoutine(routine)}
            onTriggerAchievement={(ach) => setCurrentAchievement(ach)}
            onOpenVisualTimer={(task, mins) =>
              setVisualTimerState({
                isOpen: true,
                task: task || null,
                initialMinutes: mins || 25,
              })
            }
            refresh={storage.refresh}
          />
        )}

        {activeTab === 'routines' && (
          <RoutinesListScreen
            routines={storage.routines}
            onLaunchRoutine={(routine) => setRunningRoutine(routine)}
            refresh={storage.refresh}
          />
        )}

        {activeTab === 'lexi' && (
          <LexiChatInterface
            tasks={storage.tasks}
            onOpenLiveVoice={() => setActiveOverlay('live_voice')}
            refresh={storage.refresh}
            embedded={true}
          />
        )}

        {activeTab === 'notes' && (
          <NotesScreen notes={storage.notes} refresh={storage.refresh} />
        )}

        {activeTab === 'reflect' && (
          <ReflectScreen
            todayMood={storage.todayMood}
            recentMoods={storage.recentMoods}
            refresh={storage.refresh}
          />
        )}
      </main>

      {/* Persistent Floating Capture Button (hidden on Lexi tab to avoid obscuring chat bar) */}
      {activeTab !== 'lexi' && (
        <button
          onClick={() => setIsCaptureOpen(true)}
          className="fixed bottom-20 right-5 z-40 w-13 h-13 rounded-2xl bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] flex items-center justify-center shadow-xl shadow-[#2FB083]/20 active:scale-95 transition-all"
          title="Add task or thought"
          aria-label="Add task"
        >
          <Plus className="w-6 h-6 stroke-[2.5]" />
        </button>
      )}

      {/* Bottom Navigation Bar */}
      <nav className="fixed bottom-0 left-0 right-0 z-30 bg-[#161618]/95 backdrop-blur-md border-t border-[#232326] pb-safe safe-bottom">
        <div className="max-w-2xl mx-auto flex items-center justify-around py-2 px-1">
          <button
            onClick={() => setActiveTab('today')}
            className={`flex flex-col items-center gap-1 py-1 px-3 rounded-xl transition-all ${
              activeTab === 'today'
                ? 'text-[#2FB083]'
                : 'text-[#8A8A8E] hover:text-[#F0F0F0]'
            }`}
          >
            <Sun className="w-5 h-5" />
            <span className="text-[10px] font-medium tracking-wide">Today</span>
          </button>

          <button
            onClick={() => setActiveTab('routines')}
            className={`flex flex-col items-center gap-1 py-1 px-3 rounded-xl transition-all ${
              activeTab === 'routines'
                ? 'text-[#2FB083]'
                : 'text-[#8A8A8E] hover:text-[#F0F0F0]'
            }`}
          >
            <Repeat className="w-5 h-5" />
            <span className="text-[10px] font-medium tracking-wide">Routines</span>
          </button>

          {/* Lexi AI Dedicated Tab */}
          <button
            onClick={() => setActiveTab('lexi')}
            className={`flex flex-col items-center gap-1 py-1 px-3.5 rounded-xl transition-all relative ${
              activeTab === 'lexi'
                ? 'text-[#BB86FC] font-semibold'
                : 'text-[#8A8A8E] hover:text-[#BB86FC]'
            }`}
          >
            <div
              className={`p-1 rounded-full ${
                activeTab === 'lexi' ? 'bg-[#BB86FC]/20 ring-1 ring-[#BB86FC]/40' : ''
              }`}
            >
              <Sparkles className="w-5 h-5" />
            </div>
            <span className="text-[10px] tracking-wide">Lexi AI</span>
          </button>

          <button
            onClick={() => setActiveTab('notes')}
            className={`flex flex-col items-center gap-1 py-1 px-3 rounded-xl transition-all ${
              activeTab === 'notes'
                ? 'text-[#2FB083]'
                : 'text-[#8A8A8E] hover:text-[#F0F0F0]'
            }`}
          >
            <StickyNote className="w-5 h-5" />
            <span className="text-[10px] font-medium tracking-wide">Notes</span>
          </button>

          <button
            onClick={() => setActiveTab('reflect')}
            className={`flex flex-col items-center gap-1 py-1 px-3 rounded-xl transition-all ${
              activeTab === 'reflect'
                ? 'text-[#2FB083]'
                : 'text-[#8A8A8E] hover:text-[#F0F0F0]'
            }`}
          >
            <Flower2 className="w-5 h-5" />
            <span className="text-[10px] font-medium tracking-wide">Reflect</span>
          </button>
        </div>
      </nav>

      {/* Routine Runner Overlay */}
      {runningRoutine && (
        <RoutineRunScreen
          routine={runningRoutine}
          onFinished={() => setRunningRoutine(null)}
          refresh={storage.refresh}
        />
      )}

      {/* Live Voice Screen (gemini-3.8-live) */}
      {activeOverlay === 'live_voice' && (
        <LiveVoiceScreen onClose={() => setActiveOverlay(null)} />
      )}

      {/* Google Drive Workspace Overlay */}
      {activeOverlay === 'google_drive' && (
        <div className="fixed inset-0 z-50 bg-[#0C0C0D] overflow-y-auto">
          <GoogleDriveScreen onBack={() => setActiveOverlay(null)} />
        </div>
      )}

      {/* Visual Clock Timer Modal Overlay (Time-Blindness Pomodoro) */}
      {visualTimerState.isOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm animate-in fade-in">
          <VisualClockTimer
            initialMinutes={visualTimerState.initialMinutes}
            activeTask={visualTimerState.task}
            onClose={() =>
              setVisualTimerState((prev) => ({ ...prev, isOpen: false }))
            }
            onTaskCompleted={() => {
              storage.refresh();
              setVisualTimerState((prev) => ({ ...prev, isOpen: false }));
            }}
          />
        </div>
      )}

      {/* Settings Overlay */}
      {activeOverlay === 'settings' && (
        <div className="fixed inset-0 z-50 bg-[#0C0C0D] overflow-y-auto">
          <SettingsScreen
            settings={storage.settings}
            onBack={() => setActiveOverlay(null)}
            onOpenConnectedServices={() => setActiveOverlay('connected_services')}
            onOpenHealthIntegrations={() => setActiveOverlay('health_integrations')}
            onOpenGoogleDrive={() => setActiveOverlay('google_drive')}
            refresh={storage.refresh}
          />
        </div>
      )}

      {/* Connected Services Overlay */}
      {activeOverlay === 'connected_services' && (
        <div className="fixed inset-0 z-50 bg-[#0C0C0D] overflow-y-auto">
          <ConnectedServicesScreen
            onBack={() => setActiveOverlay('settings')}
            onOpenGoogleDrive={() => setActiveOverlay('google_drive')}
          />
        </div>
      )}

      {/* Health Integrations Overlay */}
      {activeOverlay === 'health_integrations' && (
        <div className="fixed inset-0 z-50 bg-[#0C0C0D] overflow-y-auto">
          <HealthIntegrationsScreen
            workouts={storage.hevyWorkouts}
            apiKey={storage.hevyApiKey}
            onBack={() => setActiveOverlay('settings')}
            refresh={storage.refresh}
          />
        </div>
      )}

      {/* Fast Global Capture Sheet */}
      <CaptureSheet
        isOpen={isCaptureOpen}
        onClose={() => setIsCaptureOpen(false)}
        onCreated={() => storage.refresh()}
      />
    </div>
  );
};
