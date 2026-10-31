import React, { useState } from 'react';
import {
  ArrowLeft,
  ChevronRight,
  CloudSync,
  Dumbbell,
  Radio,
  RotateCcw,
  LogIn,
  LogOut,
  User as UserIcon,
  Cloud,
} from 'lucide-react';
import { AppSettings, settingsStorage } from '../lib/storage';
import { useFirebaseAuth } from '../lib/firebase';

interface SettingsScreenProps {
  settings: AppSettings;
  onBack: () => void;
  onOpenConnectedServices: () => void;
  onOpenHealthIntegrations: () => void;
  refresh: () => void;
}

export const SettingsScreen: React.FC<SettingsScreenProps> = ({
  settings,
  onBack,
  onOpenConnectedServices,
  onOpenHealthIntegrations,
  refresh,
}) => {
  const [name, setName] = useState(settings.displayName || '');
  const [briefing, setBriefing] = useState(settings.morningBriefing);
  const [cloudGemini, setCloudGemini] = useState(settings.cloudGemini);

  const { user, signInWithGoogle, signOut, syncStatus } = useFirebaseAuth();

  const handleSaveName = (newName: string) => {
    setName(newName);
    settingsStorage.save({ displayName: newName.trim() });
    refresh();
  };

  const handleToggleBriefing = () => {
    const next = !briefing;
    setBriefing(next);
    settingsStorage.save({ morningBriefing: next });
    refresh();
  };

  const handleToggleCloudGemini = () => {
    if (!cloudGemini) {
      const ok = window.confirm(
        'Enable Cloud Gemini?\n\nTask titles and descriptions will be processed for smarter executive breakdown suggestions. Health data, energy logs, and private mood check-ins are NEVER shared and remain strictly on-device.\n\nYou can turn this off at any time.'
      );
      if (!ok) return;
    }
    const next = !cloudGemini;
    setCloudGemini(next);
    settingsStorage.save({ cloudGemini: next });
    refresh();
  };

  const handleResetData = () => {
    if (
      window.confirm(
        'Reset NeuroFlow data to initial clean state? This reloads the starter routines, habits, and tasks.'
      )
    ) {
      localStorage.clear();
      window.location.reload();
    }
  };

  return (
    <div className="pb-28 max-w-2xl mx-auto px-4 pt-3 space-y-6">
      <div className="flex items-center gap-3 pb-2 border-b border-[#232326]">
        <button
          onClick={onBack}
          className="p-1.5 text-[#8A8A8E] hover:text-[#F0F0F0] rounded-xl"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div>
          <h2 className="text-lg font-semibold text-[#F0F0F0]">Settings</h2>
          <p className="text-xs text-[#8A8A8E]">Preferences & Account Security</p>
        </div>
      </div>

      {/* Firebase Account & Auth Section */}
      <div className="space-y-2">
        <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block">
          Firebase Auth & Sync
        </span>

        <div className="p-4 rounded-2xl bg-[#161618] border border-[#232326] space-y-3 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              {user?.photoURL ? (
                <img
                  src={user.photoURL}
                  alt={user.displayName || 'User'}
                  className="w-10 h-10 rounded-full border border-[#232326] object-cover"
                />
              ) : (
                <div className="w-10 h-10 rounded-full bg-[#1C1C1F] border border-[#232326] flex items-center justify-center text-[#2FB083]">
                  <UserIcon className="w-5 h-5" />
                </div>
              )}
              <div>
                <h4 className="text-sm font-medium text-[#F0F0F0]">
                  {user ? user.displayName || 'Google Account' : 'Not signed in'}
                </h4>
                <p className="text-xs text-[#8A8A8E]">
                  {user ? user.email : 'Sign in to sync your tasks and habits with Firestore'}
                </p>
              </div>
            </div>

            {user ? (
              <button
                onClick={signOut}
                className="px-3 py-1.5 rounded-xl bg-[#212124] text-[#8A8A8E] hover:text-[#D9A441] border border-[#232326] text-xs font-semibold flex items-center gap-1.5 transition-colors"
              >
                <LogOut className="w-3.5 h-3.5" />
                <span>Sign Out</span>
              </button>
            ) : (
              <button
                onClick={signInWithGoogle}
                className="px-3 py-1.5 rounded-xl bg-[#2FB083] text-[#0C0C0D] hover:bg-[#2FB083]/90 text-xs font-semibold flex items-center gap-1.5 transition-colors"
              >
                <LogIn className="w-3.5 h-3.5" />
                <span>Google Sign-In</span>
              </button>
            )}
          </div>

          {user && (
            <div className="pt-2 border-t border-[#232326] flex items-center justify-between text-xs text-[#8A8A8E]">
              <span className="flex items-center gap-1.5 text-[#2FB083]">
                <Cloud className="w-3.5 h-3.5" />
                Cloud Firestore connected
              </span>
              <span className="font-mono text-[10px] text-[#555559]">
                UID: {user.uid.slice(0, 8)}…
              </span>
            </div>
          )}
        </div>
      </div>

      {/* About you */}
      <div className="space-y-2">
        <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block">
          About you
        </span>
        <div className="p-3.5 rounded-2xl bg-[#161618] border border-[#232326]">
          <label className="text-xs text-[#8A8A8E] block mb-1">Display name</label>
          <input
            type="text"
            value={name}
            onChange={(e) => handleSaveName(e.target.value)}
            placeholder="Bryan (optional)"
            className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-sm px-3 py-2 rounded-xl border border-[#232326] focus:border-[#2FB083] outline-none"
          />
        </div>
      </div>

      {/* Integrations */}
      <div className="space-y-2">
        <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block">
          Integrations
        </span>

        <div className="space-y-2">
          <div
            onClick={onOpenConnectedServices}
            className="p-3.5 rounded-2xl bg-[#161618] hover:bg-[#1C1C1F] border border-[#232326] flex items-center justify-between cursor-pointer transition-colors"
          >
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-xl bg-[#2FB083]/10 text-[#2FB083]">
                <CloudSync className="w-4 h-4" />
              </div>
              <div>
                <h4 className="text-xs font-medium text-[#F0F0F0]">Connected Services</h4>
                <p className="text-[11px] text-[#8A8A8E]">
                  Google Tasks, Calendar, and Drive
                </p>
              </div>
            </div>
            <ChevronRight className="w-4 h-4 text-[#555559]" />
          </div>

          <div
            onClick={onOpenHealthIntegrations}
            className="p-3.5 rounded-2xl bg-[#161618] hover:bg-[#1C1C1F] border border-[#232326] flex items-center justify-between cursor-pointer transition-colors"
          >
            <div className="flex items-center gap-3">
              <div className="p-2 rounded-xl bg-[#2FB083]/10 text-[#2FB083]">
                <Dumbbell className="w-4 h-4" />
              </div>
              <div>
                <h4 className="text-xs font-medium text-[#F0F0F0]">Health Integrations</h4>
                <p className="text-[11px] text-[#8A8A8E]">
                  Hevy connection and strength workouts
                </p>
              </div>
            </div>
            <ChevronRight className="w-4 h-4 text-[#555559]" />
          </div>
        </div>
      </div>

      {/* Notifications */}
      <div className="space-y-2">
        <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block">
          Notifications
        </span>

        <div className="p-3.5 rounded-2xl bg-[#161618] border border-[#232326] flex items-center justify-between">
          <div className="pr-4">
            <h4 className="text-xs font-medium text-[#F0F0F0]">Morning briefing</h4>
            <p className="text-[11px] text-[#8A8A8E] mt-0.5">
              A quiet nudge each morning showing how many tasks are waiting.
            </p>
          </div>
          <button
            onClick={handleToggleBriefing}
            className={`w-11 h-6 rounded-full transition-colors relative p-0.5 shrink-0 ${
              briefing ? 'bg-[#2FB083]' : 'bg-[#232326]'
            }`}
          >
            <span
              className={`block w-5 h-5 rounded-full bg-white transition-transform ${
                briefing ? 'translate-x-5' : 'translate-x-0'
              }`}
            />
          </button>
        </div>
      </div>

      {/* AI & Gemini Capabilities */}
      <div className="space-y-2">
        <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block">
          Gemini AI Ecosystem
        </span>

        <div className="p-3.5 rounded-2xl bg-[#161618] border border-[#232326] space-y-3">
          <div className="flex items-center justify-between">
            <div className="pr-4">
              <h4 className="text-xs font-medium text-[#F0F0F0]">Cloud Gemini breakdown</h4>
              <p className="text-[11px] text-[#8A8A8E] mt-0.5">
                Multi-model ADHD planning using gemini-4-argon, gemini-3.8-flash, and gemini-3.1-flash-lite.
              </p>
            </div>
            <button
              onClick={handleToggleCloudGemini}
              className={`w-11 h-6 rounded-full transition-colors relative p-0.5 shrink-0 ${
                cloudGemini ? 'bg-[#2FB083]' : 'bg-[#232326]'
              }`}
            >
              <span
                className={`block w-5 h-5 rounded-full bg-white transition-transform ${
                  cloudGemini ? 'translate-x-5' : 'translate-x-0'
                }`}
              />
            </button>
          </div>

          <div className="pt-2 border-t border-[#232326] text-[11px] text-[#8A8A8E] space-y-1">
            <div className="flex items-center justify-between">
              <span>Real-Time Voice API:</span>
              <span className="text-[#BB86FC] font-mono">gemini-3.8-live</span>
            </div>
            <div className="flex items-center justify-between">
              <span>Voice Transcription:</span>
              <span className="text-[#2FB083] font-mono">gemini-3.5-transcribe</span>
            </div>
            <div className="flex items-center justify-between">
              <span>Search & Maps Grounding:</span>
              <span className="text-[#7AA7A0] font-mono">gemini-3.8-flash</span>
            </div>
          </div>
        </div>
      </div>

      {/* Data Management */}
      <div className="pt-4 border-t border-[#232326]">
        <button
          onClick={handleResetData}
          className="text-xs text-[#8A8A8E] hover:text-[#D9A441] flex items-center gap-1.5 transition-colors"
        >
          <RotateCcw className="w-3.5 h-3.5" />
          <span>Reset local data to defaults</span>
        </button>
      </div>
    </div>
  );
};
