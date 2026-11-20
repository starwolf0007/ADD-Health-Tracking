import React from 'react';
import { ArrowLeft, Dumbbell, ShieldCheck } from 'lucide-react';

interface HealthIntegrationsScreenProps {
  workouts?: any[];
  apiKey?: string;
  onBack: () => void;
  refresh: () => void;
}

export const HealthIntegrationsScreen: React.FC<HealthIntegrationsScreenProps> = ({
  onBack,
}) => {
  return (
    <div className="pb-28 max-w-2xl mx-auto px-4 pt-3 space-y-5">
      <div className="flex items-center gap-3 pb-2 border-b border-[#232326]">
        <button
          onClick={onBack}
          className="p-1.5 text-[#8A8A8E] hover:text-[#F0F0F0] rounded-xl"
          aria-label="Back to settings"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div>
          <h2 className="text-lg font-semibold text-[#F0F0F0]">Health Integrations</h2>
          <p className="text-xs text-[#8A8A8E]">Integrations status & roadmap</p>
        </div>
      </div>

      <div className="p-5 rounded-2xl bg-[#161618] border border-[#232326] space-y-3">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-[#2FB083]/10 flex items-center justify-center text-[#2FB083]">
            <ShieldCheck className="w-5 h-5" />
          </div>
          <div>
            <h3 className="text-sm font-semibold text-[#F0F0F0]">Local-First Integrity</h3>
            <p className="text-xs text-[#8A8A8E]">Zero unverified sync claims</p>
          </div>
        </div>

        <p className="text-xs text-[#A0A0A5] leading-relaxed">
          In Slice 1, external workout and fitness syncing (such as Hevy API ingestion) is deferred.
          NeuroFlow operates purely local-first. No unverified third-party sync or background telemetry runs.
        </p>

        <div className="pt-2 border-t border-[#232326] text-[11px] text-[#555559]">
          Rank 2 feature — will be introduced with verified user authorization after the core loop baseline is established.
        </div>
      </div>
    </div>
  );
};
