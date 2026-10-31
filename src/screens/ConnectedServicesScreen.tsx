import { useFirebaseAuth } from '../lib/firebase';
import { useNeuroStorage } from '../lib/storage';
import React, { useState } from 'react';
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
} from 'lucide-react';

interface ConnectedServicesScreenProps {
  onBack: () => void;
}

export const ConnectedServicesScreen: React.FC<
  ConnectedServicesScreenProps
> = ({ onBack }) => {
  const { user, signInWithGoogle, signOut, authError } = useFirebaseAuth();
  const { settings } = useNeuroStorage();
  const isConnected = !!user;
  const email = user?.email || 'Guest account';
  const name = user?.displayName || 'Signed in';

  const services = [
    {
      name: 'Google Tasks',
      desc: 'Spine sync — 2-way task synchronization',
      icon: CheckCircle2,
      status: 'Not implemented',
      color: 'text-[#2FB083]',
    },
    {
      name: 'Google Calendar',
      desc: 'Absorbs scheduled times into calendar blocks',
      icon: Calendar,
      status: 'Not implemented',
      color: 'text-[#7AA7A0]',
    },
    {
      name: 'Google Drive',
      desc: 'Lasting-value attachments & behavioral backup',
      icon: Cloud,
      status: 'Not implemented',
      color: 'text-[#8A8A8E]',
    },
    {
      name: 'Health Connect',
      desc: 'Passive steps, sleep, resting HR ingestion boundary',
      icon: Heart,
      status: 'Not implemented',
      color: 'text-[#8A8A8E]',
    },
    {
      name: 'Gemini AI',
      desc: 'Opt-in cloud intelligence for task breakdowns',
      icon: Sparkles,
      status: settings.cloudGemini ? 'Enabled; server setup required' : 'Off',
      color: 'text-[#BB86FC]',
    },
    {
      name: 'Gmail',
      desc: 'Scan recent mail for action confirmations (pull-only)',
      icon: Mail,
      status: 'Not implemented',
      color: 'text-[#8A8A8E]',
    },
    {
      name: 'Contacts',
      desc: 'Resolve-on-view for actionable call/text tasks',
      icon: Users,
      status: 'Not implemented',
      color: 'text-[#8A8A8E]',
    },
  ];

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
          <h2 className="text-lg font-semibold text-[#F0F0F0]">
            Connected Services
          </h2>
          <p className="text-xs text-[#8A8A8E]">
            Google spine and assistive integrations
          </p>
        </div>
      </div>

      {/* Account Tile */}
      <div className="p-4 rounded-2xl bg-[#161618] border border-[#232326] space-y-3 shadow-sm">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-full bg-[#1C1C1F] border border-[#232326] flex items-center justify-center text-[#2FB083]">
            <User className="w-6 h-6" />
          </div>
          <div className="flex-1 min-w-0">
            <h3 className="text-sm font-medium text-[#F0F0F0]">
              {isConnected ? name : 'Not Connected'}
            </h3>
            <p className="text-xs text-[#8A8A8E] truncate">
              {isConnected
                ? email
                : 'Google sign-in for NeuroFlow tasks and notes'}
            </p>
          </div>
          <button
            onClick={isConnected ? signOut : signInWithGoogle}
            className={`px-3 py-1.5 rounded-xl text-xs font-semibold border transition-colors ${
              isConnected
                ? 'bg-[#212124] text-[#8A8A8E] border-[#232326] hover:text-[#D9A441]'
                : 'bg-[#2FB083] text-[#0C0C0D] border-[#2FB083]'
            }`}
          >
            {isConnected ? 'Disconnect' : 'Connect'}
          </button>
        </div>
      </div>

      {authError && (
        <p role="alert" className="text-red-300 text-sm">
          {authError}
        </p>
      )}
      {/* Services List */}
      <div className="space-y-3">
        <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block">
          Services
        </span>

        <div className="space-y-2">
          {services.map((svc) => {
            const Icon = svc.icon;
            return (
              <div
                key={svc.name}
                className="p-3.5 rounded-xl bg-[#161618] border border-[#232326] flex items-center justify-between gap-3"
              >
                <div className="flex items-center gap-3 min-w-0">
                  <div className="p-2 rounded-lg bg-[#1C1C1F] text-[#2FB083]">
                    <Icon className="w-4 h-4" />
                  </div>
                  <div>
                    <h4 className="text-xs font-medium text-[#F0F0F0]">
                      {svc.name}
                    </h4>
                    <p className="text-[11px] text-[#8A8A8E] truncate mt-0.5">
                      {svc.desc}
                    </p>
                  </div>
                </div>
                <span className={`text-[11px] font-mono shrink-0 ${svc.color}`}>
                  {svc.status}
                </span>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
