import React, { useState } from 'react';
import {
  ArrowLeft,
  Dumbbell,
  RefreshCw,
  CheckCircle2,
  Clock,
  Layers,
  Key,
} from 'lucide-react';
import { HevyWorkout } from '../types';
import { hevyStorage } from '../lib/storage';

interface HealthIntegrationsScreenProps {
  workouts: HevyWorkout[];
  apiKey: string;
  onBack: () => void;
  refresh: () => void;
}

export const HealthIntegrationsScreen: React.FC<HealthIntegrationsScreenProps> = ({
  workouts,
  apiKey,
  onBack,
  refresh,
}) => {
  const [keyInput, setKeyInput] = useState(apiKey || '');
  const [isSyncing, setIsSyncing] = useState(false);
  const [statusMsg, setStatusMsg] = useState<string | null>(null);

  const isConnected = !!apiKey;

  const handleConnect = (e: React.FormEvent) => {
    e.preventDefault();
    const clean = keyInput.trim();
    if (!clean) return;
    hevyStorage.saveApiKey(clean);
    setStatusMsg('Connected to Hevy Pro API.');
    setTimeout(() => setStatusMsg(null), 3000);
    refresh();
  };

  const handleDisconnect = () => {
    if (window.confirm('Disconnect Hevy? Imported workouts will remain stored locally.')) {
      hevyStorage.saveApiKey('');
      setKeyInput('');
      setStatusMsg('Disconnected from Hevy.');
      setTimeout(() => setStatusMsg(null), 3000);
      refresh();
    }
  };

  const handleSyncNow = () => {
    setIsSyncing(true);
    setTimeout(() => {
      setIsSyncing(false);
      setStatusMsg('Workouts reconciled with Hevy.');
      setTimeout(() => setStatusMsg(null), 3000);
      refresh();
    }, 1200);
  };

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
          <h2 className="text-lg font-semibold text-[#F0F0F0]">Health Integrations</h2>
          <p className="text-xs text-[#8A8A8E]">Hevy connection and imported workouts</p>
        </div>
      </div>

      {statusMsg && (
        <div className="p-3 rounded-xl bg-[#2FB083]/15 border border-[#2FB083]/30 text-xs text-[#2FB083] font-medium">
          {statusMsg}
        </div>
      )}

      {/* Hevy Connection Card */}
      <div className="p-4 rounded-2xl bg-[#161618] border border-[#232326] space-y-3.5 shadow-sm">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-lg bg-[#2FB083]/10 flex items-center justify-center text-[#2FB083]">
              <Dumbbell className="w-4 h-4" />
            </div>
            <div>
              <h3 className="text-sm font-medium text-[#F0F0F0]">Hevy Tracker</h3>
              <p className="text-[11px] text-[#8A8A8E]">Strength & workout logger</p>
            </div>
          </div>
          <span
            className={`text-[11px] font-mono px-2 py-0.5 rounded ${
              isConnected
                ? 'bg-[#2FB083]/15 text-[#2FB083]'
                : 'bg-[#232326] text-[#8A8A8E]'
            }`}
          >
            {isConnected ? 'Connected' : 'Not Connected'}
          </span>
        </div>

        {!isConnected ? (
          <form onSubmit={handleConnect} className="space-y-3 pt-2">
            <p className="text-xs text-[#8A8A8E] leading-relaxed">
              A Hevy Pro API key is required. It is stored securely on this device and never shared.
            </p>
            <div className="flex items-center gap-2">
              <div className="relative flex-1">
                <Key className="w-4 h-4 text-[#555559] absolute left-3 top-3" />
                <input
                  type="password"
                  value={keyInput}
                  onChange={(e) => setKeyInput(e.target.value)}
                  placeholder="Enter Hevy Pro API Key"
                  className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-xs pl-9 pr-3.5 py-2.5 rounded-xl border border-[#232326] focus:border-[#2FB083] outline-none"
                />
              </div>
              <button
                type="submit"
                disabled={!keyInput.trim()}
                className="px-4 py-2.5 bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] text-xs font-semibold rounded-xl disabled:opacity-40"
              >
                Connect
              </button>
            </div>
          </form>
        ) : (
          <div className="pt-2 flex items-center justify-between">
            <button
              onClick={handleSyncNow}
              disabled={isSyncing}
              className="flex items-center gap-1.5 px-3.5 py-2 bg-[#212124] hover:bg-[#28282C] text-xs font-medium text-[#F0F0F0] rounded-xl border border-[#232326]"
            >
              <RefreshCw className={`w-3.5 h-3.5 ${isSyncing ? 'animate-spin text-[#2FB083]' : ''}`} />
              <span>{isSyncing ? 'Syncing…' : 'Sync Now'}</span>
            </button>
            <button
              onClick={handleDisconnect}
              className="text-xs text-[#8A8A8E] hover:text-[#D9A441]"
            >
              Disconnect
            </button>
          </div>
        )}
      </div>

      {/* Recent Workouts List */}
      <div className="space-y-3 pt-2">
        <div className="flex items-center justify-between">
          <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase">
            Recent Workouts ({workouts.length})
          </span>
        </div>

        <div className="space-y-3">
          {workouts.map((workout) => (
            <div
              key={workout.id}
              className="p-4 rounded-2xl bg-[#161618] border border-[#232326] space-y-3 shadow-sm"
            >
              <div className="flex items-start justify-between gap-2">
                <div>
                  <h4 className="text-sm font-medium text-[#F0F0F0]">
                    {workout.title}
                  </h4>
                  {workout.description && (
                    <p className="text-xs text-[#8A8A8E] mt-0.5">
                      {workout.description}
                    </p>
                  )}
                </div>
                <div className="text-right shrink-0">
                  <span className="text-xs text-[#8A8A8E] block">
                    {new Date(workout.startTime).toLocaleDateString([], {
                      month: 'short',
                      day: 'numeric',
                    })}
                  </span>
                  <span className="text-[10px] text-[#555559] font-mono">
                    {new Date(workout.startTime).toLocaleTimeString([], {
                      hour: '2-digit',
                      minute: '2-digit',
                    })}
                  </span>
                </div>
              </div>

              {/* Exercises summary */}
              <div className="space-y-2 pt-2 border-t border-[#232326]">
                {workout.exercises.map((ex) => (
                  <div key={ex.index} className="text-xs bg-[#1C1C1F] p-2.5 rounded-xl">
                    <div className="flex items-center justify-between font-medium text-[#F0F0F0] mb-1">
                      <span>{ex.title}</span>
                      <span className="text-[#8A8A8E] font-mono text-[11px]">
                        {ex.sets.length} sets
                      </span>
                    </div>
                    <div className="flex flex-wrap gap-1.5 pt-1">
                      {ex.sets.map((set, sIdx) => (
                        <span
                          key={sIdx}
                          className="px-2 py-0.5 rounded bg-[#212124] text-[10px] font-mono text-[#8A8A8E]"
                        >
                          {set.weightKg ? `${set.weightKg}kg × ` : ''}
                          {set.reps ? `${set.reps}` : ''}
                        </span>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
