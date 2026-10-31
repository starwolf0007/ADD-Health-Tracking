import React, { useState } from 'react';
import {
  Sun,
  StickyNote,
  Repeat,
  Sparkles,
  Settings,
  Plus,
  Flower2,
} from 'lucide-react';
import { Routine, Achievement } from '../types';
import { useNeuroStorage } from '../lib/storage';
import { TodayScreen } from '../screens/TodayScreen';
import { NotesScreen } from '../screens/NotesScreen';
import { RoutinesListScreen } from '../screens/RoutinesListScreen';
import { ReflectScreen } from '../screens/ReflectScreen';
import { RoutineRunScreen } from '../screens/RoutineRunScreen';
import { SettingsScreen } from '../screens/SettingsScreen';
import { ConnectedServicesScreen } from '../screens/ConnectedServicesScreen';
import { HealthIntegrationsScreen } from '../screens/HealthIntegrationsScreen';
import { LexiConversationScreen } from '../screens/LexiConversationScreen';
import { CaptureSheet } from './CaptureSheet';
import { AchievementToast } from './AchievementToast';

export const AppShell: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'today' | 'notes' | 'routines' | 'reflect'>('today');
  const [activeOverlay, setActiveOverlay] = useState<
    'settings' | 'connected_services' | 'health_integrations' | 'lexi' | null
  >(null);
  const [runningRoutine, setRunningRoutine] = useState<Routine | null>(null);
  const [isCaptureOpen, setIsCaptureOpen] = useState(false);
  const [currentAchievement, setCurrentAchievement] = useState<Achievement | null>(null);

  const storage = useNeuroStorage();

  const greetingName = storage.settings.displayName;

  return (
    <div className="min-h-screen bg-[#0C0C0D] text-[#F0F0F0] flex flex-col selection:bg-[#2FB083]/30">
      {/* Achievement Toast Host */}
      <AchievementToast
        achievement={currentAchievement}
        onDismiss={() => setCurrentAchievement(null)}
      />

      {/* Top Header */}
      <header className="sticky top-0 z-30 bg-[#0C0C0D]/90 backdrop-blur-md border-b border-[#232326] px-4 py-3 flex items-center justify-between max-w-2xl mx-auto w-full">
        <div>
          <h1 className="text-lg font-medium text-[#F0F0F0]">
            {greetingName ? `Hey, ${greetingName}` : 'Today'}
          </h1>
        </div>
        <button
          onClick={() => setActiveOverlay('settings')}
          className="p-2 text-[#8A8A8E] hover:text-[#F0F0F0] hover:bg-[#161618] rounded-xl transition-colors"
          title="Settings"
          aria-label="Settings"
        >
          <Settings className="w-5 h-5" />
        </button>
      </header>

      {/* Primary Tab View */}
      <main className="flex-1 max-w-2xl mx-auto w-full">
        {activeTab === 'today' && (
          <TodayScreen
            tasks={storage.tasks}
            routines={storage.routines}
            habits={storage.habits}
            todayMood={storage.todayMood}
            onOpenLexi={() => setActiveOverlay('lexi')}
            onOpenSettings={() => setActiveOverlay('settings')}
            onLaunchRoutine={(routine) => setRunningRoutine(routine)}
            onTriggerAchievement={(ach) => setCurrentAchievement(ach)}
            refresh={storage.refresh}
          />
        )}

        {activeTab === 'notes' && (
          <NotesScreen notes={storage.notes} refresh={storage.refresh} />
        )}

        {activeTab === 'routines' && (
          <RoutinesListScreen
            routines={storage.routines}
            onLaunchRoutine={(routine) => setRunningRoutine(routine)}
            refresh={storage.refresh}
          />
        )}

        {activeTab === 'reflect' && (
          <ReflectScreen
            todayMood={storage.todayMood}
            recentMoods={storage.recentMoods}
            refresh={storage.refresh}
          />
        )}
      </main>

      {/* Persistent Floating Capture Button (Spec §13: reachable from anywhere in one gesture) */}
      <button
        onClick={() => setIsCaptureOpen(true)}
        className="fixed bottom-20 right-5 z-40 w-13 h-13 rounded-2xl bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] flex items-center justify-center shadow-xl shadow-[#2FB083]/20 active:scale-95 transition-all"
        title="Add task or thought"
        aria-label="Add task"
      >
        <Plus className="w-6 h-6 stroke-[2.5]" />
      </button>

      {/* Bottom Navigation Bar */}
      <nav className="fixed bottom-0 left-0 right-0 z-30 bg-[#161618]/95 backdrop-blur-md border-t border-[#232326] pb-safe safe-bottom">
        <div className="max-w-2xl mx-auto flex items-center justify-around py-2 px-2">
          <button
            onClick={() => setActiveTab('today')}
            className={`flex flex-col items-center gap-1 py-1 px-4 rounded-xl transition-all ${
              activeTab === 'today'
                ? 'text-[#2FB083]'
                : 'text-[#8A8A8E] hover:text-[#F0F0F0]'
            }`}
          >
            <Sun className="w-5 h-5" />
            <span className="text-[10px] font-medium tracking-wide">Today</span>
          </button>

          <button
            onClick={() => setActiveTab('notes')}
            className={`flex flex-col items-center gap-1 py-1 px-4 rounded-xl transition-all ${
              activeTab === 'notes'
                ? 'text-[#2FB083]'
                : 'text-[#8A8A8E] hover:text-[#F0F0F0]'
            }`}
          >
            <StickyNote className="w-5 h-5" />
            <span className="text-[10px] font-medium tracking-wide">Notes</span>
          </button>

          <button
            onClick={() => setActiveTab('routines')}
            className={`flex flex-col items-center gap-1 py-1 px-4 rounded-xl transition-all ${
              activeTab === 'routines'
                ? 'text-[#2FB083]'
                : 'text-[#8A8A8E] hover:text-[#F0F0F0]'
            }`}
          >
            <Repeat className="w-5 h-5" />
            <span className="text-[10px] font-medium tracking-wide">Routines</span>
          </button>

          <button
            onClick={() => setActiveTab('reflect')}
            className={`flex flex-col items-center gap-1 py-1 px-4 rounded-xl transition-all ${
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

      {/* Settings Overlay */}
      {activeOverlay === 'settings' && (
        <div className="fixed inset-0 z-50 bg-[#0C0C0D] overflow-y-auto">
          <SettingsScreen
            settings={storage.settings}
            onBack={() => setActiveOverlay(null)}
            onOpenConnectedServices={() => setActiveOverlay('connected_services')}
            onOpenHealthIntegrations={() => setActiveOverlay('health_integrations')}
            refresh={storage.refresh}
          />
        </div>
      )}

      {/* Connected Services Overlay */}
      {activeOverlay === 'connected_services' && (
        <div className="fixed inset-0 z-50 bg-[#0C0C0D] overflow-y-auto">
          <ConnectedServicesScreen onBack={() => setActiveOverlay('settings')} />
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

      {/* Lexi Conversation Overlay */}
      {activeOverlay === 'lexi' && (
        <LexiConversationScreen
          tasks={storage.tasks}
          onBack={() => setActiveOverlay(null)}
          refresh={storage.refresh}
        />
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
