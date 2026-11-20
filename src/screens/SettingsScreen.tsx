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
  AlertTriangle,
} from 'lucide-react';
import {
  AppSettings,
  settingsStorage,
  resetCurrentLocalData,
  getGuestDataSummary,
  importGuestDataToAccount,
  exportAllData,
  getStorageScope,
  formatDateKey,
} from '../lib/storage';
import { useFirebaseAuth, useDriveBackupHealth } from '../lib/firebase';

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
    authError,
    triggerManualSync,
  } = useFirebaseAuth();
  const backupHealth = useDriveBackupHealth();
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
    resetCurrentLocalData();
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
          <p className="text-xs text-[#8A8A8E]">Preferences & Account</p>
        </div>
      </div>

      {/* Account Section */}
      <div className="p-4 rounded-2xl bg-[#161618] border border-[#232326] space-y-3">
        <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block">
          Account & Device Sync
        </span>

        {user ? (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                {user.photoURL ? (
                  <img
                    src={user.photoURL}
                    alt={user.displayName || 'User'}
                    className="w-10 h-10 rounded-full border border-[#232326]"
                  />
                ) : (
                  <div className="w-10 h-10 rounded-full bg-[#1C1C1F] border border-[#232326] flex items-center justify-center text-[#2FB083]">
                    <UserIcon className="w-5 h-5" />
                  </div>
                )}
                <div>
                  <h4 className="text-xs font-medium text-[#F0F0F0]">
                    {user.displayName || 'Google Account'}
                  </h4>
                  <p className="text-[11px] text-[#8A8A8E]">{user.email}</p>
                </div>
              </div>

              <button
                onClick={signOut}
                className="p-2 rounded-xl bg-[#212124] text-[#8A8A8E] hover:text-[#D9A441] border border-[#232326] transition-colors"
                title="Sign out of Google"
              >
                <LogOut className="w-4 h-4" />
              </button>
            </div>

            {/* Sync telemetry bar */}
            <div className="pt-2 border-t border-[#232326] flex items-center justify-between text-xs text-[#8A8A8E]">
              <div className="flex items-center gap-1.5">
                <Cloud className="w-3.5 h-3.5 text-[#2FB083]" />
                <span>
                  {syncStatus === 'synced'
                    ? 'Cloud backup in sync'
                    : syncStatus === 'syncing'
                    ? 'Syncing changes…'
                    : syncStatus === 'offline'
                    ? 'Offline mode (queued)'
                    : 'Sync pending'}
                </span>
              </div>
              <button
                disabled={isSyncingNow}
                onClick={async () => {
                  setIsSyncingNow(true);
                  try {
                    await triggerManualSync();
                  } finally {
                    setTimeout(() => setIsSyncingNow(false), 800);
                  }
                }}
                className="flex items-center gap-1 text-[11px] text-[#2FB083] hover:underline disabled:opacity-50"
              >
                <RefreshCw className={`w-3 h-3 ${isSyncingNow ? 'animate-spin' : ''}`} />
                <span>Sync now</span>
              </button>
            </div>

            {pendingQueueCount > 0 && (
              <div className="text-[11px] text-[#D9A441] flex items-center gap-1">
                <span>·</span>
                <span>{pendingQueueCount} offline items pending</span>
              </div>
            )}
          </div>
        ) : (
          <div className="flex items-center justify-between">
            <div>
              <h4 className="text-xs font-medium text-[#F0F0F0]">Sign in with Google</h4>
              <p className="text-[11px] text-[#8A8A8E]">
                Save tasks and notes securely to Google Cloud
              </p>
            </div>
            <button
              onClick={signInWithGoogle}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] font-semibold text-xs shadow-sm transition-all"
            >
              <LogIn className="w-3.5 h-3.5 stroke-[2.5]" />
              <span>Connect</span>
            </button>
          </div>
        )}

        {authError && (
          <p role="alert" className="text-red-300 text-xs mt-2">
            {authError}
          </p>
        )}
      </div>

      {/* General Settings */}
      <div className="space-y-3">
        <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block">
          General
        </span>

        {/* Display Name */}
        <div className="p-3.5 rounded-2xl bg-[#161618] border border-[#232326] space-y-2">
          <label className="text-xs font-medium text-[#F0F0F0] block">
            What should Lexi call you?
          </label>
          <input
            type="text"
            value={name}
            onChange={(e) => handleSaveName(e.target.value)}
            placeholder="e.g. Bryan"
            className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-sm px-3.5 py-2 rounded-xl border border-[#232326] focus:border-[#2FB083] outline-none transition-colors"
          />
        </div>

        {/* Morning Briefing */}
        <div className="p-3.5 rounded-2xl bg-[#161618] border border-[#232326] flex items-center justify-between">
          <div className="pr-4">
            <h4 className="text-xs font-medium text-[#F0F0F0]">
              Show Morning Briefing Banner
            </h4>
            <p className="text-[11px] text-[#8A8A8E] mt-0.5">
              Friendly greeting and daily focus cue at top of Today screen
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

      {/* Connected Services & Integrations */}
      <div className="space-y-3">
        <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block">
          Spine & Integrations
        </span>

        {/* Google Drive Workspace Navigation */}
        <div
          onClick={onOpenGoogleDrive}
          className="p-3.5 rounded-2xl bg-[#161618] hover:bg-[#1C1C1F] border border-[#232326] flex items-center justify-between cursor-pointer transition-colors"
        >
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-xl bg-[#4285F4]/20 text-[#4285F4]">
              <HardDrive className="w-4 h-4" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h4 className="text-xs font-medium text-[#F0F0F0]">Google Drive Workspace</h4>
                <span
                  className={`text-[10px] font-mono px-1.5 py-0.5 rounded ${
                    backupHealth.status === 'error' || backupHealth.status === 'token_expired'
                      ? 'bg-red-950/60 text-red-300'
                      : backupHealth.lastSyncedAt
                      ? 'bg-[#2FB083]/20 text-[#2FB083]'
                      : 'bg-[#232326] text-[#8A8A8E]'
                  }`}
                >
                  {backupHealth.lastSyncedAt ? 'Active' : 'Ready'}
                </span>
              </div>
              <p className="text-[11px] text-[#8A8A8E]">
                Behavioral backup snapshots & lasting-value attachments
              </p>
            </div>
          </div>
          <ChevronRight className="w-4 h-4 text-[#8A8A8E]" />
        </div>

        {/* Auto Drive Backup Toggle */}
        <div className="p-3.5 rounded-2xl bg-[#161618] border border-[#232326] flex items-center justify-between">
          <div className="pr-4">
            <div className="flex items-center gap-1.5">
              <FolderSync className="w-3.5 h-3.5 text-[#4285F4]" />
              <h4 className="text-xs font-medium text-[#F0F0F0]">
                Automatic Google Drive Daily Backup
              </h4>
            </div>
            <p className="text-[11px] text-[#8A8A8E] mt-0.5">
              Saves a daily JSON snapshot to your Google Drive when signed in. Sensitive health data is excluded.
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

        {/* Connected Services Navigation */}
        <div
          onClick={onOpenConnectedServices}
          className="p-3.5 rounded-2xl bg-[#161618] hover:bg-[#1C1C1F] border border-[#232326] flex items-center justify-between cursor-pointer transition-colors"
        >
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-xl bg-[#1C1C1F] text-[#2FB083]">
              <CloudSync className="w-4 h-4" />
            </div>
            <div>
              <h4 className="text-xs font-medium text-[#F0F0F0]">Connected Services</h4>
              <p className="text-[11px] text-[#8A8A8E]">
                Google Tasks, Calendar, and Drive status
              </p>
            </div>
          </div>
          <ChevronRight className="w-4 h-4 text-[#8A8A8E]" />
        </div>

        {/* Health Integrations Navigation */}
        <div
          onClick={onOpenHealthIntegrations}
          className="p-3.5 rounded-2xl bg-[#161618] hover:bg-[#1C1C1F] border border-[#232326] flex items-center justify-between cursor-pointer transition-colors"
        >
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-xl bg-[#1C1C1F] text-[#D9A441]">
              <Dumbbell className="w-4 h-4" />
            </div>
            <div>
              <h4 className="text-xs font-medium text-[#F0F0F0]">Health Integrations</h4>
              <p className="text-[11px] text-[#8A8A8E]">Deferred in Slice 1 (Local-first only)</p>
            </div>
          </div>
          <ChevronRight className="w-4 h-4 text-[#8A8A8E]" />
        </div>
      </div>

      {/* Cloud & Assistant Gating */}
      <div className="space-y-3">
        <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block">
          Cloud Intelligence (Opt-in)
        </span>

        <div className="p-3.5 rounded-2xl bg-[#161618] border border-[#232326] space-y-3">
          <div className="flex items-center justify-between">
            <div className="pr-4">
              <h4 className="text-xs font-medium text-[#F0F0F0]">
                Cloud Gemini breakdown
              </h4>
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

          {/* Explicit Privacy & Consent Confirmation Modal/Banner */}
          {showCloudConsentConfirm && (
            <div className="p-3.5 rounded-xl bg-[#1C1C1F] border border-[#2FB083]/40 space-y-2.5">
              <div className="flex items-start gap-2 text-xs text-[#F0F0F0]">
                <ShieldCheck className="w-4 h-4 text-[#2FB083] shrink-0 mt-0.5" />
                <div>
                  <span className="font-semibold text-[#2FB083] block mb-1">
                    Enable Cloud Gemini Companion?
                  </span>
                  <p className="text-[#8A8A8E] text-[11px] leading-relaxed">
                    Messages, conversation context, recorded audio, and location (when using Maps) are sent to Google Gemini. Do not include private health information in messages. Google sign-in is required.
                  </p>
                </div>
              </div>
              <div className="flex items-center justify-end gap-2 pt-1">
                <button
                  type="button"
                  onClick={() => setShowCloudConsentConfirm(false)}
                  className="px-3 py-1.5 rounded-lg bg-[#212124] text-[#8A8A8E] hover:text-[#F0F0F0] text-xs font-medium transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  onClick={handleConfirmEnableCloudGemini}
                  className="px-3 py-1.5 rounded-lg bg-[#2FB083] text-[#0C0C0D] text-xs font-semibold hover:bg-[#2FB083]/90 transition-colors"
                >
                  I Understand & Enable
                </button>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Data Management & Account Migration */}
      <div className="space-y-3">
        <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block">
          Data Management
        </span>

        {/* Guest Data Import (When signed in and guest data exists) */}
        {user && guestSummary.hasData && (
          <div className="p-3.5 rounded-2xl bg-[#161618] border border-[#D9A441]/40 space-y-2.5">
            <div className="flex items-start justify-between">
              <div>
                <h4 className="text-xs font-medium text-[#F0F0F0]">Import Guest Data to Account</h4>
                <p className="text-[11px] text-[#8A8A8E] mt-0.5">
                  Found on this device: {guestSummary.taskCount} tasks, {guestSummary.routineCount} routines, {guestSummary.noteCount} notes.
                </p>
              </div>
              <button
                type="button"
                onClick={() => {
                  const res = importGuestDataToAccount(user.uid);
                  setGuestSummary(getGuestDataSummary());
                  setMergeNotice(`Imported ${res.importedTasks} tasks and ${res.importedNotes} notes to your account.`);
                  refresh();
                }}
                className="px-3 py-1.5 rounded-xl bg-[#D9A441] text-[#0C0C0D] text-xs font-semibold hover:bg-[#D9A441]/90 transition-colors shrink-0"
              >
                Merge to Account
              </button>
            </div>
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
                Reset this account’s local cache? Pending task/note uploads are retained.
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
