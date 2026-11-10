import React from 'react';
import {
  ArrowLeft,
  CheckCircle2,
  Calendar,
  Cloud,
  Heart,
  Sparkles,
  Mail,
  User,
  Users,
  HardDrive,
  ChevronRight,
  AlertTriangle,
} from 'lucide-react';
import { useFirebaseAuth, useDriveBackupHealth } from '../lib/firebase';

interface ConnectedServicesScreenProps {
  onBack: () => void;
  onOpenGoogleDrive?: () => void;
}

export const ConnectedServicesScreen: React.FC<ConnectedServicesScreenProps> = ({
  onBack,
  onOpenGoogleDrive,
}) => {
  const { user, accessToken, signInWithGoogle, signOut } = useFirebaseAuth();
  const backupHealth = useDriveBackupHealth();

  return (
    <div className="pb-28 max-w-2xl mx-auto px-4 pt-3 space-y-5">
      <div className="flex items-center gap-3 pb-2 border-b border-[#232326]">
        <button
          onClick={onBack}
          className="p-1.5 text-[#8A8A8E] hover:text-[#F0F0F0] rounded-xl"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div>
          <h2 className="text-lg font-semibold text-[#F0F0F0]">Connected Services</h2>
          <p className="text-xs text-[#8A8A8E]">Google Workspace and Assistive Integrations</p>
        </div>
      </div>

      {/* Account Tile */}
      <div className="p-4 rounded-2xl bg-[#161618] border border-[#232326] space-y-3 shadow-sm">
        <div className="flex items-center gap-3">
          {user?.photoURL ? (
            <img
              src={user.photoURL}
              alt={user.displayName || 'User'}
              className="w-12 h-12 rounded-full border border-[#232326] object-cover"
            />
          ) : (
            <div className="w-12 h-12 rounded-full bg-[#1C1C1F] border border-[#232326] flex items-center justify-center text-[#2FB083]">
              <User className="w-6 h-6" />
            </div>
          )}
          <div className="flex-1 min-w-0">
            <h3 className="text-sm font-medium text-[#F0F0F0]">
              {user ? user.displayName || 'Google Account' : 'Not Connected'}
            </h3>
            <p className="text-xs text-[#8A8A8E] truncate">
              {user ? user.email : 'Sign in to access Google Drive & Workspace services'}
            </p>
          </div>
          {user ? (
            <button
              onClick={signOut}
              className="px-3 py-1.5 rounded-xl text-xs font-semibold bg-[#212124] text-[#8A8A8E] border border-[#232326] hover:text-[#D9A441] transition-colors"
            >
              Disconnect
            </button>
          ) : (
            <button
              onClick={signInWithGoogle}
              className="px-3 py-1.5 rounded-xl text-xs font-semibold bg-[#2FB083] text-[#0C0C0D] border border-[#2FB083] hover:bg-[#2FB083]/90 transition-colors"
            >
              Connect
            </button>
          )}
        </div>
      </div>

      {/* Google Drive Primary Workspace Banner */}
      <div className="p-4 rounded-2xl bg-[#1C1C1F] border border-[#4285F4]/30 space-y-2 shadow-md">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="p-2 rounded-xl bg-[#4285F4]/20 text-[#4285F4]">
              <HardDrive className="w-5 h-5" />
            </div>
            <div>
              <h4 className="text-sm font-semibold text-[#F0F0F0]">Google Drive</h4>
              <p className="text-xs text-[#8A8A8E]">
                {accessToken ? 'Connected & Authorized (drive.file)' : 'OAuth Scopes configured'}
              </p>
            </div>
          </div>
          <span
            className={`text-xs font-mono px-2 py-0.5 rounded-full ${
              backupHealth.status === 'error' || backupHealth.status === 'token_expired'
                ? 'bg-red-950/60 text-red-300 border border-red-800/50'
                : accessToken
                ? 'bg-[#2FB083]/15 text-[#2FB083] border border-[#2FB083]/30'
                : 'bg-[#D9A441]/15 text-[#D9A441] border border-[#D9A441]/30'
            }`}
          >
            {backupHealth.status === 'error'
              ? 'Sync Error'
              : backupHealth.status === 'token_expired'
              ? 'Token Expired'
              : accessToken
              ? 'Active'
              : 'Setup Ready'}
          </span>
        </div>

        <p className="text-xs text-[#8A8A8E] leading-relaxed pt-1">
          Store lasting-value attachments, export automated backups of your routines and tasks, and manage files on Google Drive.
        </p>

        <div className="pt-1 border-t border-[#232326] flex items-center justify-between text-[11px] text-[#8A8A8E]">
          <span>Last Synced:</span>
          <span className="font-mono text-[#F0F0F0]">
            {backupHealth.lastSyncedAt
              ? new Date(backupHealth.lastSyncedAt).toLocaleString([], {
                  dateStyle: 'short',
                  timeStyle: 'short',
                })
              : 'Never synced'}
          </span>
        </div>

        {backupHealth.syncError && (
          <div className="p-2 rounded-xl bg-red-950/40 border border-red-800/40 text-[11px] text-red-300 flex items-center gap-1.5">
            <AlertTriangle className="w-3.5 h-3.5 text-red-400 shrink-0" />
            <span className="truncate">{backupHealth.syncError}</span>
          </div>
        )}

        {onOpenGoogleDrive && (
          <div className="pt-2">
            <button
              onClick={onOpenGoogleDrive}
              className="w-full py-2.5 px-4 rounded-xl bg-[#4285F4] hover:bg-[#4285F4]/90 text-white font-semibold text-xs flex items-center justify-center gap-2 shadow-md transition-all active:scale-98"
            >
              <span>Open Google Drive Workspace</span>
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        )}
      </div>

      {/* Other Connected Services */}
      <div className="space-y-3">
        <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block">
          Other Services
        </span>

        <div className="space-y-2">
          <div className="p-3.5 rounded-xl bg-[#161618] border border-[#232326] flex items-center justify-between gap-3">
            <div className="flex items-center gap-3 min-w-0">
              <div className="p-2 rounded-lg bg-[#1C1C1F] text-[#8A8A8E]">
                <CheckCircle2 className="w-4 h-4" />
              </div>
              <div>
                <h4 className="text-xs font-medium text-[#F0F0F0]">Google Tasks</h4>
                <p className="text-[11px] text-[#8A8A8E] truncate mt-0.5">
                  Two-way task synchronization · Planned for Phase E
                </p>
              </div>
            </div>
            <span className="text-[10px] font-mono text-[#8A8A8E] bg-[#212124] px-2 py-0.5 rounded-md border border-[#232326]">
              Planned (Phase E)
            </span>
          </div>

          <div className="p-3.5 rounded-xl bg-[#161618] border border-[#232326] flex items-center justify-between gap-3">
            <div className="flex items-center gap-3 min-w-0">
              <div className="p-2 rounded-lg bg-[#1C1C1F] text-[#8A8A8E]">
                <Calendar className="w-4 h-4" />
              </div>
              <div>
                <h4 className="text-xs font-medium text-[#F0F0F0]">Google Calendar</h4>
                <p className="text-[11px] text-[#8A8A8E] truncate mt-0.5">
                  Read-only Anchor blocks · Planned for Phase E
                </p>
              </div>
            </div>
            <span className="text-[10px] font-mono text-[#8A8A8E] bg-[#212124] px-2 py-0.5 rounded-md border border-[#232326]">
              Planned (Phase E)
            </span>
          </div>

          <div className="p-3.5 rounded-xl bg-[#161618] border border-[#232326] flex items-center justify-between gap-3">
            <div className="flex items-center gap-3 min-w-0">
              <div className="p-2 rounded-lg bg-[#1C1C1F] text-[#BB86FC]">
                <Sparkles className="w-4 h-4" />
              </div>
              <div>
                <h4 className="text-xs font-medium text-[#F0F0F0]">Gemini AI</h4>
                <p className="text-[11px] text-[#8A8A8E] truncate mt-0.5">
                  Live voice, executive coaching, search & maps grounding
                </p>
              </div>
            </div>
            <span className="text-[11px] font-mono text-[#BB86FC]">Active</span>
          </div>
        </div>
      </div>
    </div>
  );
};
