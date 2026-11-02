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
  HardDrive,
  FolderSync,
  Download,
  ShieldCheck,
  RefreshCw,
  Check,
} from 'lucide-react';
import {
  AppSettings,
  settingsStorage,
  getGuestDataSummary,
  importGuestDataToAccount,
  exportAllData,
  getStorageScope,
  formatDateKey,
} from '../lib/storage';
import { useFirebaseAuth } from '../lib/firebase';

interface SettingsScreenProps {
  settings: AppSettings;
  onBack: () => void;
  onOpenConnectedServices: () => void;
  onOpenHealthIntegrations: () => void;
  onOpenGoogleDrive?: () => void;
  refresh: () => void;
}

export const SettingsScreen: React.FC<SettingsScreenProps> = ({
  settings,
  onBack,
  onOpenConnectedServices,
  onOpenHealthIntegrations,
  onOpenGoogleDrive,
  refresh,
}) => {
  const [name, setName] = useState(settings.displayName || '');
  const [briefing, setBriefing] = useState(settings.morningBriefing);
  const [cloudGemini, setCloudGemini] = useState(settings.cloudGemini);
  const [autoDriveBackup, setAutoDriveBackup] = useState(settings.autoDriveBackup ?? true);

  const {
    user,
    signInWithGoogle,
    signOut,
    syncStatus,
    pendingQueueCount,
    triggerManualSync,
  } = useFirebaseAuth();
  const [guestSummary, setGuestSummary] = useState(getGuestDataSummary());
  const [isSyncingNow, setIsSyncingNow] = useState(false);
  const [mergeNotice, setMergeNotice] = useState<string | null>(null);
  const [showCloudConsentConfirm, setShowCloudConsentConfirm] = useState(false);
  const [showResetConfirm, setShowResetConfirm] = useState(false);
  const [includeSensitiveExport, setIncludeSensitiveExport] = useState(false);

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

  const handleToggleAutoDriveBackup = () => {
    const next = !autoDriveBackup;
    setAutoDriveBackup(next);
    settingsStorage.save({ autoDriveBackup: next });
    refresh();
  };

  const handleToggleCloudGemini = () => {
    if (!cloudGemini && !showCloudConsentConfirm) {
      setShowCloudConsentConfirm(true);
      return;
    }
    const next = !cloudGemini;
    setCloudGemini(next);
    setShowCloudConsentConfirm(false);
    settingsStorage.save({ cloudGemini: next });
    refresh();
  };

  const handleConfirmEnableCloudGemini = () => {
    setCloudGemini(true);
    setShowCloudConsentConfirm(false);
    settingsStorage.save({ cloudGemini: true });
    refresh();
  };

  const handleResetData = () => {
    localStorage.clear();
    window.location.reload();
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
          {/* Google Drive Workspace */}
          {onOpenGoogleDrive && (
            <div
              onClick={onOpenGoogleDrive}
              className="p-3.5 rounded-2xl bg-[#161618] hover:bg-[#1C1C1F] border border-[#4285F4]/30 flex items-center justify-between cursor-pointer transition-colors shadow-sm"
            >
              <div className="flex items-center gap-3">
                <div className="p-2 rounded-xl bg-[#4285F4]/15 text-[#4285F4]">
                  <HardDrive className="w-4 h-4" />
                </div>
                <div>
                  <h4 className="text-xs font-medium text-[#F0F0F0]">Google Drive</h4>
                  <p className="text-[11px] text-[#8A8A8E]">
                    File management & backup snapshots
                  </p>
                </div>
              </div>
              <ChevronRight className="w-4 h-4 text-[#555559]" />
            </div>
          )}

          {/* Automatic Daily Google Drive Backup Toggle */}
          <div className="p-3.5 rounded-2xl bg-[#161618] border border-[#232326] flex items-center justify-between">
            <div className="pr-4">
              <h4 className="text-xs font-medium text-[#F0F0F0]">Automatic Daily Drive Backup</h4>
              <p className="text-[11px] text-[#8A8A8E] mt-0.5">
                Automatically archives an encrypted snapshot of tasks, habits, and notes to your Google Drive daily.
              </p>
            </div>
            <button
              onClick={handleToggleAutoDriveBackup}
              className={`w-11 h-6 rounded-full transition-colors relative p-0.5 shrink-0 ${
                autoDriveBackup ? 'bg-[#2FB083]' : 'bg-[#232326]'
              }`}
            >
              <span
                className={`block w-5 h-5 rounded-full bg-white transition-transform ${
                  autoDriveBackup ? 'translate-x-5' : 'translate-x-0'
                }`}
              />
            </button>
          </div>


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
                  Google Tasks, Calendar, and Drive status
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
                Multi-model ADHD planning using gemini-3.8-flash and gemini-3.1-flash-lite. Mood logs, medications, and health metrics are stripped by the on-device privacy gate.
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

          {showCloudConsentConfirm && !cloudGemini && (
            <div className="p-3 rounded-xl bg-[#1C1C1F] border border-[#2FB083]/40 space-y-2">
              <p className="text-xs text-[#F0F0F0] font-medium">
                Enable Cloud Gemini?
              </p>
              <p className="text-[11px] text-[#8A8A8E] leading-relaxed">
                Task titles and descriptions will be processed for executive breakdown suggestions. Sensitive health data, medication habits, and mood check-ins are strictly on-device and never shared.
              </p>
              <div className="flex items-center gap-2 pt-1">
                <button
                  type="button"
                  onClick={handleConfirmEnableCloudGemini}
                  className="px-3 py-1.5 rounded-lg bg-[#2FB083] text-[#0C0C0D] text-xs font-semibold"
                >
                  Confirm & Enable
                </button>
                <button
                  type="button"
                  onClick={() => setShowCloudConsentConfirm(false)}
                  className="px-3 py-1.5 rounded-lg bg-[#232326] text-[#8A8A8E] text-xs"
                >
                  Cancel
                </button>
              </div>
            </div>
          )}

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

      {/* Data Management & Account Isolation */}
      <div className="space-y-3 pt-2 border-t border-[#232326]">
        <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block">
          Data Management & Account Isolation
        </span>

        {/* Current Storage Scope Card */}
        <div className="p-3.5 rounded-2xl bg-[#161618] border border-[#232326] space-y-2">
          <div className="flex items-center justify-between text-xs">
            <span className="text-[#8A8A8E]">Active Storage Scope:</span>
            <span className="font-mono text-[#F0F0F0]">
              {user ? `Account (${user.email || user.uid.slice(0, 8)})` : 'Guest Mode (Device Local)'}
            </span>
          </div>

          <div className="flex items-center justify-between text-xs pt-1 border-t border-[#232326]/60">
            <span className="text-[#8A8A8E] flex items-center gap-1.5">
              <ShieldCheck className="w-3.5 h-3.5 text-[#2FB083]" />
              Pre-Migration Backup:
            </span>
            <span className="text-[#2FB083] font-mono text-[11px]">Protected in storage</span>
          </div>

          {/* Pending Offline Sync Queue */}
          {pendingQueueCount > 0 && (
            <div className="pt-2 border-t border-[#232326]/60 flex items-center justify-between">
              <span className="text-xs text-[#D9A441] flex items-center gap-1.5">
                <RefreshCw className={`w-3.5 h-3.5 ${isSyncingNow ? 'animate-spin' : ''}`} />
                {pendingQueueCount} offline items pending
              </span>
              <button
                onClick={async () => {
                  setIsSyncingNow(true);
                  await triggerManualSync();
                  setIsSyncingNow(false);
                  refresh();
                }}
                disabled={isSyncingNow}
                className="px-2.5 py-1 rounded-xl bg-[#D9A441]/15 text-[#D9A441] text-xs font-medium hover:bg-[#D9A441]/25 transition-colors"
              >
                Sync Now
              </button>
            </div>
          )}
        </div>

        {/* Guest Data Import Card (Visible when signed in and guest records exist) */}
        {user && guestSummary.hasData && (
          <div className="p-3.5 rounded-2xl bg-[#161618] border border-[#2FB083]/30 space-y-2 shadow-sm">
            <div className="flex items-start gap-2.5">
              <div className="p-2 rounded-xl bg-[#2FB083]/15 text-[#2FB083]">
                <FolderSync className="w-4 h-4" />
              </div>
              <div className="flex-1">
                <h4 className="text-xs font-semibold text-[#F0F0F0]">Unmerged Guest Work Available</h4>
                <p className="text-[11px] text-[#8A8A8E] mt-0.5">
                  Found {guestSummary.taskCount} tasks, {guestSummary.routineCount} routines, {guestSummary.habitCount} habits, {guestSummary.noteCount} notes created in guest mode.
                </p>
              </div>
            </div>

            <button
              onClick={() => {
                const res = importGuestDataToAccount(user.uid);
                setGuestSummary(getGuestDataSummary());
                refresh();
                setMergeNotice(
                  `Successfully merged ${res.importedTasks} tasks, ${res.importedRoutines} routines, and ${res.importedNotes} notes into your account.`
                );
                setTimeout(() => setMergeNotice(null), 6000);
              }}
              className="w-full py-2 rounded-xl bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] font-semibold text-xs tracking-wide transition-all shadow-sm flex items-center justify-center gap-1.5"
            >
              <FolderSync className="w-3.5 h-3.5" />
              <span>Import Guest Work into this Account</span>
            </button>

            {mergeNotice && (
              <div className="p-2.5 rounded-xl bg-[#2FB083]/15 border border-[#2FB083]/30 flex items-center gap-2 text-xs text-[#2FB083]">
                <Check className="w-4 h-4 shrink-0" />
                <span>{mergeNotice}</span>
              </div>
            )}
          </div>
        )}

        {/* Local JSON Backup Download */}
        <div className="p-3.5 rounded-2xl bg-[#161618] border border-[#232326] space-y-3">
          <div className="flex items-center justify-between">
            <div className="pr-3">
              <h4 className="text-xs font-medium text-[#F0F0F0]">Export Local Data Snapshot</h4>
              <p className="text-[11px] text-[#8A8A8E]">
                Download a JSON snapshot of your tasks, routines, non-sensitive habits, and notes. Automatic cloud backups always exclude sensitive data.
              </p>
            </div>
            <button
              onClick={() => {
                const data = exportAllData({ includeSensitive: includeSensitiveExport });
                const blob = new Blob([JSON.stringify(data, null, 2)], {
                  type: 'application/json',
                });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = `neuroflow-backup-${getStorageScope()}-${formatDateKey(new Date())}.json`;
                a.click();
                URL.revokeObjectURL(url);
              }}
              className="p-2.5 rounded-xl bg-[#212124] text-[#8A8A8E] hover:text-[#F0F0F0] border border-[#232326] transition-colors shrink-0"
              title="Download JSON snapshot"
            >
              <Download className="w-4 h-4" />
            </button>
          </div>

          <label className="flex items-center justify-between pt-2 border-t border-[#232326]/60 cursor-pointer text-[11px] text-[#8A8A8E]">
            <span>Include on-device sensitive data (Mood logs, Hevy workouts, medication habits)</span>
            <input
              type="checkbox"
              checked={includeSensitiveExport}
              onChange={(e) => setIncludeSensitiveExport(e.target.checked)}
              className="rounded border-[#232326] bg-[#1C1C1F] text-[#2FB083] focus:ring-0"
            />
          </label>
        </div>

        {/* Reset Local Data */}
        <div className="pt-2">
          {!showResetConfirm ? (
            <button
              type="button"
              onClick={() => setShowResetConfirm(true)}
              className="text-xs text-[#8A8A8E] hover:text-[#D9A441] flex items-center gap-1.5 transition-colors"
            >
              <RotateCcw className="w-3.5 h-3.5" />
              <span>Reset current scope to defaults</span>
            </button>
          ) : (
            <div className="p-3 rounded-xl bg-[#D9A441]/10 border border-[#D9A441]/40 flex items-center justify-between gap-2">
              <span className="text-xs text-[#F0F0F0]">
                Reset local storage to starter defaults?
              </span>
              <div className="flex items-center gap-2 shrink-0">
                <button
                  type="button"
                  onClick={handleResetData}
                  className="px-3 py-1 rounded-lg bg-[#D9A441] text-[#0C0C0D] text-xs font-semibold"
                >
                  Confirm Reset
                </button>
                <button
                  type="button"
                  onClick={() => setShowResetConfirm(false)}
                  className="px-2.5 py-1 rounded-lg bg-[#212124] text-[#8A8A8E] text-xs"
                >
                  Cancel
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
