import React, { useState, useRef, useEffect } from 'react';
import {
  Sparkles,
  Send,
  Check,
  Globe,
  MapPin,
  Mic,
  Square,
  Radio,
  ExternalLink,
  Plus,
  Loader2,
  Brain,
  Zap,
  Coffee,
  HelpCircle,
  BatteryLow,
  Users,
  Smile,
  AlertCircle,
  Clock,
  RotateCcw,
  X,
} from 'lucide-react';
import { Task, LexiProposal } from '../types';
import { LexiAvatar } from './LexiAvatar';
import { taskStorage, settingsStorage } from '../lib/storage';
import { useAudioTranscribe } from '../lib/useTranscribe';

interface GroundingSource {
  uri: string;
  title: string;
}

interface GroundingPlace {
  title: string;
  uri: string;
  placeAnswerSources?: any;
}

export interface SuggestedMicroStep {
  id: string;
  title: string;
  energy: 'low' | 'medium' | 'high';
  estimatedMinutes: number;
}

export interface ChatMessage {
  id: string;
  sender: 'lexi' | 'user';
  text: string;
  modelUsed?: string;
  proposal?: LexiProposal;
  suggestedSteps?: SuggestedMicroStep[];
  sources?: GroundingSource[];
  places?: GroundingPlace[];
  isBodyDoubleCheckin?: boolean;
  isQuotaError?: boolean;
  isConsentRequired?: boolean;
  failedPrompt?: string;
}

interface LexiChatInterfaceProps {
  tasks: Task[];
  onOpenLiveVoice?: () => void;
  refresh: () => void;
  embedded?: boolean;
}

export const LexiChatInterface: React.FC<LexiChatInterfaceProps> = ({
  tasks,
  onOpenLiveVoice,
  refresh,
  embedded = false,
}) => {
  const pendingTasks = tasks.filter((t) => t.status !== 'completed');
  const activeTask = tasks.find((t) => t.status === 'inProgress') || pendingTasks[0] || null;

  const [input, setInput] = useState('');
  const [selectedModel, setSelectedModel] = useState<
    'gemini-3.8-flash' | 'gemini-4-argon' | 'gemini-3.1-flash-lite'
  >('gemini-3.1-flash-lite');
  const [activeTool, setActiveTool] = useState<'none' | 'search' | 'maps'>('none');
  const [isGenerating, setIsGenerating] = useState(false);

  const activeAbortControllerRef = useRef<AbortController | null>(null);
  const activeRequestIdRef = useRef<string | null>(null);

  const handleCancelRequest = () => {
    if (activeAbortControllerRef.current) {
      activeAbortControllerRef.current.abort();
      activeAbortControllerRef.current = null;
    }
    setIsGenerating(false);
  };

  // Proactive Body Doubling State
  const [isBodyDoubling, setIsBodyDoubling] = useState(false);
  const [bodyDoubleSeconds, setBodyDoubleSeconds] = useState(0);
  const bodyDoubleTimerRef = useRef<number | null>(null);

  const [messages, setMessages] = useState<ChatMessage[]>(() => [
    {
      id: 'lexi-welcome',
      sender: 'lexi',
      text: activeTask
        ? `Hey! I'm Lexi, your executive function coach and body doubler. Right now, your active focus is "${activeTask.title}".\n\nNeed advice breaking it down into 2-minute steps, overcoming inertia, or starting a silent body-doubling sprint? Choose an advice prompt below or type what's on your mind.`
        : `Hey! I'm Lexi, your executive function coach. Your day is completely open.\n\nWhether you need help deciding where to start, finding a quiet focus spot, or beating procrastination, I'm here to offer small, friction-free steps.`,
      proposal: activeTask
        ? {
            type: 'start_task',
            payload: { taskId: activeTask.id },
            requiresConfirmation: true,
            confirmationPrompt: `Would you like to start "${activeTask.title}" now?`,
          }
        : undefined,
    },
  ]);

  const [appliedActions, setAppliedActions] = useState<Record<string, boolean>>({});
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Audio transcription hook (gemini-3.5-transcribe)
  const { isRecording, isTranscribing, startRecording, stopAndTranscribe } =
    useAudioTranscribe();

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages, isGenerating]);

  // Body doubling interval ticker and proactive check-in triggers
  useEffect(() => {
    if (isBodyDoubling) {
      bodyDoubleTimerRef.current = window.setInterval(() => {
        setBodyDoubleSeconds((prev) => {
          const next = prev + 1;
          // Trigger a gentle proactive check-in after every 10 minutes (600 seconds)
          if (next > 0 && next % 600 === 0) {
            triggerBodyDoubleCheckin();
          }
          return next;
        });
      }, 1000);
    } else {
      if (bodyDoubleTimerRef.current) clearInterval(bodyDoubleTimerRef.current);
      setBodyDoubleSeconds(0);
    }

    return () => {
      if (bodyDoubleTimerRef.current) clearInterval(bodyDoubleTimerRef.current);
    };
  }, [isBodyDoubling, activeTask]);

  const triggerBodyDoubleCheckin = () => {
    const taskName = activeTask ? `"${activeTask.title}"` : 'your current focus';
    setMessages((prev) => [
      ...prev,
      {
        id: `checkin-${Date.now()}`,
        sender: 'lexi',
        text: `Hey! I am right here sitting with you as your body double. How are you feeling with ${taskName}? Still flowing, or did you hit friction?`,
        isBodyDoubleCheckin: true,
      },
    ]);
  };

  const handleMicToggle = async () => {
    if (!isRecording) {
      await startRecording();
    } else {
      const transcript = await stopAndTranscribe();
      if (transcript) {
        setInput((prev) => (prev ? `${prev} ${transcript}` : transcript));
      }
    }
  };

  const handleSend = async (textToSend?: string, forcedModel?: string, forcedTool?: string) => {
    const text = (textToSend || input).trim();
    if (!text || isGenerating) return;

    const userMsg: ChatMessage = {
      id: `user-${Date.now()}`,
      sender: 'user',
      text,
    };

    const currentSettings = settingsStorage.get();
    if (!currentSettings.cloudGemini) {
      setMessages((prev) => [
        ...prev,
        userMsg,
        {
          id: `lexi-${Date.now()}`,
          sender: 'lexi',
          text: "Cloud AI Coaching is currently disabled in your Settings. To protect your privacy, conversation history is not transmitted to Google AI without your explicit consent.\n\nWould you like to enable Cloud AI to chat with Lexi?",
          isConsentRequired: true,
          failedPrompt: text,
        },
      ]);
      if (!textToSend) setInput('');
      return;
    }

    setMessages((prev) => [...prev, userMsg]);
    if (!textToSend) setInput('');
    setIsGenerating(true);

    const modelToUse = forcedModel || selectedModel;
    const toolToUse = forcedTool || activeTool;

    // Coordinated client-side deadline & cancellation
    if (activeAbortControllerRef.current) {
      activeAbortControllerRef.current.abort();
    }
    const controller = new AbortController();
    activeAbortControllerRef.current = controller;
    const reqId = `req_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`;
    activeRequestIdRef.current = reqId;

    const clientTimeoutMs = 26000;
    const timeoutId = setTimeout(() => {
      if (activeRequestIdRef.current === reqId) {
        console.warn(`[${reqId}] Client deadline (${clientTimeoutMs}ms) reached. Aborting.`);
        controller.abort();
      }
    }, clientTimeoutMs);

    try {
      if (toolToUse === 'search') {
        // Search Grounding route (gemini-3.8-flash + googleSearch)
        const res = await fetch('/api/gemini/search', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'x-request-id': reqId },
          body: JSON.stringify({ query: text }),
          signal: controller.signal,
        });
        const data = await res.json();
        if (data.error) throw new Error(data.error);

        setMessages((prev) => [
          ...prev,
          {
            id: `lexi-${Date.now()}`,
            sender: 'lexi',
            text: data.text || 'Here is what I found from Google Search.',
            modelUsed: 'gemini-3.8-flash (Search Grounded)',
            sources: data.sources || [],
          },
        ]);
      } else if (toolToUse === 'maps') {
        // Maps Grounding route (gemini-3.8-flash + googleMaps)
        let lat: number | undefined;
        let lng: number | undefined;
        try {
          if (navigator.geolocation) {
            const pos = await new Promise<GeolocationPosition>((res, rej) =>
              navigator.geolocation.getCurrentPosition(res, rej, { timeout: 3000 })
            );
            lat = pos.coords.latitude;
            lng = pos.coords.longitude;
          }
        } catch {}

        const res = await fetch('/api/gemini/maps', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'x-request-id': reqId },
          body: JSON.stringify({
            query: text,
            latitude: lat,
            longitude: lng,
          }),
          signal: controller.signal,
        });
        const data = await res.json();
        if (data.error) throw new Error(data.error);

        setMessages((prev) => [
          ...prev,
          {
            id: `lexi-${Date.now()}`,
            sender: 'lexi',
            text: data.text || 'Here are sensory-friendly and quiet places near you.',
            modelUsed: 'gemini-3.8-flash (Maps Grounded)',
            places: data.places || [],
          },
        ]);
      } else {
        // Multi-Turn Executive Function Chat route
        const executiveSystemPrompt = `You are Lexi, an empathetic, non-judgmental ADHD executive function coach and virtual body double.
Your primary goals:
1. Provide practical, highly specific executive function advice (e.g. task initiation, working memory offloading, body doubling, time blindness management, cognitive friction reduction).
2. When a user asks to break down a project or task, output exactly 3 sequential, concrete steps. Ensure Step 1 is an absurdly small initiation action taking under 2 minutes (e.g., "Open document and title it").
3. Validate low energy and eliminate shame.
4. Keep responses encouraging, concise, and structured.`;

        const history = [...messages, userMsg].map((m) => ({
          role: m.sender === 'user' ? 'user' : 'assistant',
          content: m.text,
        }));

        const res = await fetch('/api/gemini/chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'x-request-id': reqId },
          body: JSON.stringify({
            messages: history,
            model: modelToUse,
            systemInstruction: executiveSystemPrompt,
          }),
          signal: controller.signal,
        });
        const data = await res.json();
        if (data.error) throw new Error(data.error);

        // Parse real micro-steps dynamically from the LLM response if present
        let suggestedSteps: SuggestedMicroStep[] | undefined;
        const replyText = data.reply || '';
        const lines = replyText.split('\n');
        const extracted: SuggestedMicroStep[] = [];

        for (const line of lines) {
          const trimmed = line.trim();
          // Match lines like "1. Open document", "Step 1: Open document", "- Step 1: ...", "1) ..."
          const stepMatch = trimmed.match(/^(?:[-*]\s*)?(?:Step\s*\d+[:.]|\d+[.)])\s+(.+)$/i);
          if (stepMatch && stepMatch[1]) {
            const stepTitle = stepMatch[1].replace(/[*_#]/g, '').trim();
            if (stepTitle.length >= 3 && stepTitle.length <= 140) {
              const stepIndex = extracted.length + 1;
              extracted.push({
                id: `step-${stepIndex}-${Date.now()}`,
                title: stepTitle.startsWith('Step') ? stepTitle : `Step ${stepIndex}: ${stepTitle}`,
                energy: stepIndex === 1 ? 'low' : stepIndex === 2 ? 'low' : 'medium',
                estimatedMinutes: stepIndex === 1 ? 2 : stepIndex === 2 ? 5 : 10,
              });
            }
          }
        }

        if (extracted.length > 0) {
          suggestedSteps = extracted.slice(0, 6);
        }

        setMessages((prev) => [
          ...prev,
          {
            id: `lexi-${Date.now()}`,
            sender: 'lexi',
            text: data.reply || 'I am right here with you. What feels like the least resistant step?',
            modelUsed: data.model,
            suggestedSteps,
          },
        ]);
      }
    } catch (err: any) {
      if (err?.name === 'AbortError') {
        console.log(`[${reqId}] Request was aborted or cancelled.`);
        setMessages((prev) => [
          ...prev,
          {
            id: `lexi-${Date.now()}`,
            sender: 'lexi',
            text: 'Request was cancelled. Take your time—let me know whenever you want to try again.',
            failedPrompt: text,
            isQuotaError: true,
          },
        ]);
        return;
      }

      console.warn('Lexi chat interaction notice:', err?.message || err);

      const errString = typeof err?.message === 'string' ? err.message : JSON.stringify(err);
      const isQuota =
        errString.includes('429') ||
        errString.includes('503') ||
        errString.includes('RESOURCE_EXHAUSTED') ||
        errString.includes('quota') ||
        errString.includes('demand') ||
        err?.status === 429;

      const userFriendlyMessage = isQuota
        ? "I'm catching my breath for just a moment (Gemini API rate limit or high demand). Take a gentle pause with me, and tap retry below in a few seconds."
        : `I had trouble connecting (${err.message || 'connection issue'}). Let me know if you would like to try again.`;

      setMessages((prev) => [
        ...prev,
        {
          id: `lexi-${Date.now()}`,
          sender: 'lexi',
          text: userFriendlyMessage,
          isQuotaError: isQuota,
          failedPrompt: text,
        },
      ]);
    } finally {
      clearTimeout(timeoutId);
      if (activeRequestIdRef.current === reqId) {
        setIsGenerating(false);
        activeAbortControllerRef.current = null;
      }
    }
  };

  const handleAddStepToToday = (step: SuggestedMicroStep) => {
    const newTask: Task = {
      id: `task-${Date.now()}-${Math.random().toString(36).substring(2, 6)}`,
      title: step.title,
      energy: step.energy,
      status: 'pending',
      createdAt: new Date().toISOString(),
      estimatedMinutes: step.estimatedMinutes,
      isQuickWin: step.energy === 'low',
    };

    taskStorage.save(newTask);
    setAppliedActions((prev) => ({ ...prev, [step.id]: true }));
    refresh();
  };

  const handleConfirmProposal = (msgId: string, proposal: LexiProposal) => {
    if (proposal.type === 'start_task') {
      taskStorage.startTask(proposal.payload.taskId);
    } else if (proposal.type === 'pause_task') {
      taskStorage.pauseTask(proposal.payload.taskId);
    } else if (proposal.type === 'create_reentry_note') {
      taskStorage.pauseTask(
        proposal.payload.taskId,
        proposal.payload.nextAction || 'Open task to resume'
      );
    }

    setAppliedActions((prev) => ({ ...prev, [msgId]: true }));
    refresh();
  };

  const formatTimer = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  };

  return (
    <div
      className={`flex flex-col bg-[#0C0C0D] text-[#F0F0F0] ${
        embedded ? 'h-[calc(100vh-140px)]' : 'h-full'
      }`}
    >
      {/* Top Header Card */}
      <div className="p-3.5 border-b border-[#232326] bg-[#161618] flex items-center justify-between">
        <div className="flex items-center gap-3">
          <LexiAvatar size={42} visualState={isGenerating ? 'thinking' : 'idle'} />
          <div>
            <div className="flex items-center gap-1.5">
              <h2 className="text-sm sm:text-base font-semibold text-[#F0F0F0]">Lexi AI</h2>
              <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-[#BB86FC]/15 text-[#BB86FC] border border-[#BB86FC]/30">
                Executive Coach
              </span>
            </div>
            <p className="text-xs text-[#8A8A8E]">ADHD Initiation & Proactive Body Doubler</p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {/* Body Doubler Toggle */}
          <button
            onClick={() => setIsBodyDoubling(!isBodyDoubling)}
            className={`flex items-center gap-1 px-2.5 py-1.5 rounded-xl text-xs font-semibold border transition-all ${
              isBodyDoubling
                ? 'bg-[#2FB083]/20 text-[#2FB083] border-[#2FB083] shadow-md shadow-[#2FB083]/20'
                : 'bg-[#1C1C1F] text-[#8A8A8E] hover:text-[#F0F0F0] border-[#232326]'
            }`}
            title="Start virtual body-doubling session with Lexi"
          >
            <Users className="w-3.5 h-3.5" />
            <span className="hidden sm:inline">
              {isBodyDoubling ? 'Body Doubling Active' : 'Body Double'}
            </span>
          </button>

          {onOpenLiveVoice && (
            <button
              onClick={onOpenLiveVoice}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#BB86FC]/15 hover:bg-[#BB86FC]/25 text-[#BB86FC] text-xs font-semibold border border-[#BB86FC]/30 shadow-sm transition-all"
              title="Start real-time voice conversation"
            >
              <Radio className="w-3.5 h-3.5 animate-pulse" />
              <span>Voice</span>
            </button>
          )}
        </div>
      </div>

      {/* Body Doubling Banner (if active) */}
      {isBodyDoubling && (
        <div className="px-4 py-2 bg-[#2FB083]/15 border-b border-[#2FB083]/30 flex items-center justify-between text-xs text-[#2FB083] animate-in fade-in">
          <div className="flex items-center gap-2">
            <span className="w-2.5 h-2.5 rounded-full bg-[#2FB083] animate-pulse" />
            <span className="font-medium">
              Body Doubling with Lexi on {activeTask ? `"${activeTask.title}"` : 'your focus'}
            </span>
          </div>
          <div className="flex items-center gap-3 font-mono">
            <span>{formatTimer(bodyDoubleSeconds)}</span>
            <button
              onClick={() => setIsBodyDoubling(false)}
              className="text-[11px] underline opacity-80 hover:opacity-100"
            >
              Stop
            </button>
          </div>
        </div>
      )}

      {/* Advice Presets Carousel */}
      <div className="px-4 py-2 bg-[#121214] border-b border-[#232326] overflow-x-auto no-scrollbar flex items-center gap-2">
        <button
          onClick={() => {
            setSelectedModel('gemini-4-argon');
            setActiveTool('none');
            handleSend(
              'I have a task that feels way too big and overwhelming. Can you help me break it down into 3 tiny physical steps that take under 2 minutes each?',
              'gemini-4-argon',
              'none'
            );
          }}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#1C1C1F] hover:bg-[#232326] text-xs text-[#F0F0F0] border border-[#232326] whitespace-nowrap transition-colors"
        >
          <Brain className="w-3.5 h-3.5 text-[#BB86FC]" />
          <span>Break down a big task</span>
        </button>

        <button
          onClick={() => {
            setSelectedModel('gemini-3.8-flash');
            setActiveTool('none');
            handleSend(
              'I am experiencing task paralysis and cannot get started. What is one absurdly small initiation action I can do right this second?',
              'gemini-3.8-flash',
              'none'
            );
          }}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#1C1C1F] hover:bg-[#232326] text-xs text-[#F0F0F0] border border-[#232326] whitespace-nowrap transition-colors"
        >
          <Zap className="w-3.5 h-3.5 text-[#2FB083]" />
          <span>Break task paralysis</span>
        </button>

        <button
          onClick={() => {
            setIsBodyDoubling(true);
            handleSend("Let's do a quiet body-doubling focus block together. Keep me company while I start.");
          }}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#1C1C1F] hover:bg-[#232326] text-xs text-[#F0F0F0] border border-[#232326] whitespace-nowrap transition-colors"
        >
          <Users className="w-3.5 h-3.5 text-[#4285F4]" />
          <span>Start body doubling</span>
        </button>

        <button
          onClick={() => {
            setSelectedModel('gemini-3.1-flash-lite');
            setActiveTool('none');
            handleSend(
              'My energy is completely depleted today. How do I pivot my schedule so I do not feel guilty?',
              'gemini-3.1-flash-lite',
              'none'
            );
          }}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#1C1C1F] hover:bg-[#232326] text-xs text-[#F0F0F0] border border-[#232326] whitespace-nowrap transition-colors"
        >
          <BatteryLow className="w-3.5 h-3.5 text-[#D9A441]" />
          <span>Low energy pivot</span>
        </button>

        <button
          onClick={() => {
            setActiveTool('maps');
            handleSend(
              'Find quiet, low-sensory study spaces, libraries, or coffee shops near me.',
              'gemini-3.8-flash',
              'maps'
            );
          }}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#1C1C1F] hover:bg-[#232326] text-xs text-[#F0F0F0] border border-[#232326] whitespace-nowrap transition-colors"
        >
          <MapPin className="w-3.5 h-3.5 text-[#7AA7A0]" />
          <span>Quiet spaces nearby</span>
        </button>

        <button
          onClick={() => {
            setActiveTool('search');
            handleSend(
              'What does recent neuroscience say about ADHD time blindness and how to manage it?',
              'gemini-3.8-flash',
              'search'
            );
          }}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#1C1C1F] hover:bg-[#232326] text-xs text-[#F0F0F0] border border-[#232326] whitespace-nowrap transition-colors"
        >
          <Globe className="w-3.5 h-3.5 text-[#2FB083]" />
          <span>ADHD research</span>
        </button>
      </div>

      {/* Model & Tool Configuration Selector */}
      <div className="px-4 py-2 bg-[#161618] border-b border-[#232326] flex items-center justify-between text-xs gap-3">
        <div className="flex items-center gap-2">
          <span className="text-[10px] font-semibold text-[#8A8A8E] uppercase tracking-wider">
            Model:
          </span>
          <select
            value={selectedModel}
            onChange={(e) => setSelectedModel(e.target.value as any)}
            className="bg-[#212124] text-[#F0F0F0] text-xs px-2.5 py-1 rounded-lg border border-[#232326] outline-none"
          >
            <option value="gemini-3.1-flash-lite">gemini-3.1-flash-lite (Fast & Reliable · Default)</option>
            <option value="gemini-3.8-flash">gemini-3.8-flash (Balanced)</option>
            <option value="gemini-4-argon">gemini-4-argon (Deep Planning)</option>
          </select>
        </div>

        {/* Tool Grounding Toggles */}
        <div className="flex items-center gap-1.5">
          <button
            onClick={() => setActiveTool(activeTool === 'search' ? 'none' : 'search')}
            className={`flex items-center gap-1 px-2.5 py-1 rounded-lg border text-xs transition-colors ${
              activeTool === 'search'
                ? 'bg-[#2FB083]/20 text-[#2FB083] border-[#2FB083]/40'
                : 'bg-[#212124] text-[#8A8A8E] border-[#232326]'
            }`}
            title="Google Search Grounding"
          >
            <Globe className="w-3 h-3" />
            <span>Search</span>
          </button>

          <button
            onClick={() => setActiveTool(activeTool === 'maps' ? 'none' : 'maps')}
            className={`flex items-center gap-1 px-2.5 py-1 rounded-lg border text-xs transition-colors ${
              activeTool === 'maps'
                ? 'bg-[#7AA7A0]/20 text-[#7AA7A0] border-[#7AA7A0]/40'
                : 'bg-[#212124] text-[#8A8A8E] border-[#232326]'
            }`}
            title="Google Maps Grounding"
          >
            <MapPin className="w-3 h-3" />
            <span>Maps</span>
          </button>
        </div>
      </div>

      {/* Messages Thread */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {messages.map((msg) => (
          <div
            key={msg.id}
            className={`flex flex-col ${
              msg.sender === 'user' ? 'items-end' : 'items-start'
            }`}
          >
            <div
              className={`max-w-[88%] rounded-2xl p-4 text-xs sm:text-sm leading-relaxed ${
                msg.sender === 'user'
                  ? 'bg-[#2FB083] text-[#0C0C0D] font-medium rounded-tr-sm'
                  : 'bg-[#161618] text-[#F0F0F0] border border-[#232326] rounded-tl-sm shadow-md'
              }`}
            >
              <p className="whitespace-pre-wrap">{msg.text}</p>

              {/* Grounded Search Sources */}
              {msg.sources && msg.sources.length > 0 && (
                <div className="mt-3 pt-2.5 border-t border-[#232326] space-y-1.5">
                  <span className="text-[10px] font-semibold text-[#2FB083] uppercase flex items-center gap-1">
                    <Globe className="w-3 h-3" />
                    Verified Sources:
                  </span>
                  <div className="flex flex-wrap gap-1.5">
                    {msg.sources.map((src, idx) => (
                      <a
                        key={idx}
                        href={src.uri}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="flex items-center gap-1 px-2 py-1 rounded-md bg-[#212124] hover:bg-[#28282C] text-[11px] text-[#2FB083] border border-[#232326] transition-colors"
                      >
                        <span className="truncate max-w-[150px]">{src.title || src.uri}</span>
                        <ExternalLink className="w-2.5 h-2.5 shrink-0" />
                      </a>
                    ))}
                  </div>
                </div>
              )}

              {/* Grounded Maps Places */}
              {msg.places && msg.places.length > 0 && (
                <div className="mt-3 pt-2.5 border-t border-[#232326] space-y-1.5">
                  <span className="text-[10px] font-semibold text-[#7AA7A0] uppercase flex items-center gap-1">
                    <MapPin className="w-3 h-3" />
                    Recommended Quiet Spaces:
                  </span>
                  <div className="space-y-1.5">
                    {msg.places.map((place, idx) => (
                      <a
                        key={idx}
                        href={place.uri}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="flex items-center justify-between p-2 rounded-lg bg-[#212124] hover:bg-[#28282C] text-xs text-[#F0F0F0] border border-[#232326] transition-colors"
                      >
                        <span className="font-medium truncate">{place.title}</span>
                        <div className="flex items-center gap-1 text-[11px] text-[#7AA7A0] shrink-0 ml-2">
                          <span>Open Maps</span>
                          <ExternalLink className="w-3 h-3" />
                        </div>
                      </a>
                    ))}
                  </div>
                </div>
              )}

              {/* Body Double Checkin Action Responses */}
              {msg.isBodyDoubleCheckin && (
                <div className="mt-3 pt-2.5 border-t border-[#232326] flex flex-wrap gap-2">
                  <button
                    onClick={() =>
                      handleSend('Still flowing smoothly! Let us keep the session going.')
                    }
                    className="px-3 py-1.5 rounded-lg bg-[#2FB083]/20 hover:bg-[#2FB083]/30 text-[#2FB083] text-xs font-medium border border-[#2FB083]/40 transition-colors"
                  >
                    Still in the flow
                  </button>
                  <button
                    onClick={() =>
                      handleSend('I got distracted and lost my place. Help me take a tiny step to get back.')
                    }
                    className="px-3 py-1.5 rounded-lg bg-[#D9A441]/20 hover:bg-[#D9A441]/30 text-[#D9A441] text-xs font-medium border border-[#D9A441]/40 transition-colors"
                  >
                    Got distracted
                  </button>
                  <button
                    onClick={() => {
                      if (activeTask) taskStorage.complete(activeTask.id);
                      refresh();
                      handleSend('I completed this task! What a win.');
                    }}
                    className="px-3 py-1.5 rounded-lg bg-[#BB86FC]/20 hover:bg-[#BB86FC]/30 text-[#BB86FC] text-xs font-medium border border-[#BB86FC]/40 transition-colors"
                  >
                    Finished it!
                  </button>
                </div>
              )}

              {/* Quota limit recovery buttons */}
              {msg.isQuotaError && msg.failedPrompt && (
                <div className="mt-3 pt-2.5 border-t border-[#232326] flex flex-wrap gap-2">
                  <button
                    onClick={() => handleSend(msg.failedPrompt, 'gemini-3.1-flash-lite')}
                    className="px-3 py-1.5 rounded-lg bg-[#2FB083]/20 hover:bg-[#2FB083]/30 text-[#2FB083] text-xs font-semibold border border-[#2FB083]/40 flex items-center gap-1.5 transition-colors"
                  >
                    <RotateCcw className="w-3.5 h-3.5" />
                    <span>Retry with Flash Lite</span>
                  </button>
                  <button
                    onClick={() => handleSend(msg.failedPrompt)}
                    className="px-3 py-1.5 rounded-lg bg-[#1C1C1F] hover:bg-[#232326] text-[#8A8A8E] text-xs font-medium border border-[#232326] transition-colors"
                  >
                    Retry Standard
                  </button>
                </div>
              )}

              {/* Cloud AI Consent Action Card */}
              {msg.isConsentRequired && msg.failedPrompt && (
                <div className="mt-3 pt-2.5 border-t border-[#232326] flex items-center gap-2">
                  <button
                    onClick={() => {
                      settingsStorage.save({ cloudGemini: true });
                      handleSend(msg.failedPrompt);
                    }}
                    className="px-3 py-1.5 rounded-lg bg-[#2FB083] text-[#0C0C0D] text-xs font-semibold hover:bg-[#2FB083]/90 transition-colors flex items-center gap-1.5"
                  >
                    <Check className="w-3.5 h-3.5" />
                    <span>Enable Cloud AI & Proceed</span>
                  </button>
                </div>
              )}

              {msg.modelUsed && (
                <span className="block text-[10px] text-[#555559] mt-2 font-mono">
                  {msg.modelUsed}
                </span>
              )}
            </div>

            {/* Structured Micro-Steps (Multi-step Task Breakdown) */}
            {msg.suggestedSteps && msg.suggestedSteps.length > 0 && (
              <div className="mt-2.5 max-w-[88%] bg-[#1A1A1D] border border-[#2FB083]/40 rounded-xl p-3.5 shadow-md space-y-2.5">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-1.5 text-[11px] font-semibold text-[#2FB083] uppercase">
                    <Sparkles className="w-3.5 h-3.5" />
                    <span>Micro-Steps for Today</span>
                  </div>
                  <span className="text-[10px] text-[#8A8A8E]">Add any step to schedule</span>
                </div>

                <div className="space-y-2">
                  {msg.suggestedSteps.map((step) => {
                    const isAdded = appliedActions[step.id];
                    return (
                      <div
                        key={step.id}
                        className="p-2.5 rounded-lg bg-[#161618] border border-[#232326] flex items-center justify-between gap-2"
                      >
                        <div className="min-w-0">
                          <p className="text-xs text-[#F0F0F0] font-medium truncate">
                            {step.title}
                          </p>
                          <span className="text-[10px] font-mono text-[#8A8A8E]">
                            ~{step.estimatedMinutes} min · {step.energy} energy
                          </span>
                        </div>

                        {isAdded ? (
                          <div className="flex items-center gap-1 text-[11px] text-[#2FB083] font-medium shrink-0">
                            <Check className="w-3.5 h-3.5" />
                            <span>Added</span>
                          </div>
                        ) : (
                          <button
                            onClick={() => handleAddStepToToday(step)}
                            className="flex items-center gap-1 px-2.5 py-1 bg-[#2FB083]/15 hover:bg-[#2FB083]/25 text-[#2FB083] border border-[#2FB083]/30 rounded-lg text-xs font-semibold shrink-0 transition-colors"
                          >
                            <Plus className="w-3 h-3" />
                            <span>Add</span>
                          </button>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
            )}

            {/* Context Proposal Card */}
            {msg.proposal && (
              <div className="mt-2 max-w-[88%] bg-[#1A1A1D] border border-[#2FB083]/30 rounded-xl p-3 shadow-md">
                <p className="text-xs text-[#F0F0F0] mb-2 font-medium">
                  {msg.proposal.confirmationPrompt}
                </p>

                {appliedActions[msg.id] ? (
                  <div className="flex items-center gap-1.5 text-xs text-[#2FB083] font-medium">
                    <Check className="w-4 h-4" />
                    <span>Confirmed</span>
                  </div>
                ) : (
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => handleConfirmProposal(msg.id, msg.proposal!)}
                      className="px-3 py-1.5 bg-[#2FB083] text-[#0C0C0D] rounded-lg text-xs font-semibold hover:bg-[#2FB083]/90 transition-colors"
                    >
                      Start Now
                    </button>
                    <button
                      onClick={() =>
                        setAppliedActions((prev) => ({ ...prev, [msg.id]: true }))
                      }
                      className="px-2.5 py-1.5 text-xs text-[#8A8A8E] hover:text-[#F0F0F0]"
                    >
                      Dismiss
                    </button>
                  </div>
                )}
              </div>
            )}
          </div>
        ))}

        {isGenerating && (
          <div className="flex items-center justify-between p-3 rounded-2xl bg-[#161618] border border-[#232326] text-xs text-[#8A8A8E] animate-pulse">
            <div className="flex items-center gap-2">
              <Loader2 className="w-3.5 h-3.5 animate-spin text-[#2FB083]" />
              <span>Lexi is formulating executive advice…</span>
            </div>
            <button
              onClick={handleCancelRequest}
              className="px-2.5 py-1 rounded-lg bg-[#212124] hover:bg-[#28282C] text-[#F0F0F0] text-xs font-medium border border-[#232326] flex items-center gap-1 transition-colors"
            >
              <X className="w-3 h-3 text-[#8A8A8E]" />
              <span>Cancel</span>
            </button>
          </div>
        )}

        <div ref={messagesEndRef} />
      </div>

      {/* Dictation Banner */}
      {(isRecording || isTranscribing) && (
        <div className="px-4 py-2 bg-[#2FB083]/15 text-xs text-[#2FB083] flex items-center justify-between border-t border-[#2FB083]/20">
          <span className="flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-red-500 animate-ping" />
            {isRecording
              ? 'Listening to your voice… tap mic to finish dictating with gemini-3.5-transcribe'
              : 'Transcribing speech with Gemini…'}
          </span>
        </div>
      )}

      {/* Input Composer */}
      <div className="p-3 bg-[#161618] border-t border-[#232326] flex items-center gap-2">
        <button
          onClick={handleMicToggle}
          className={`p-2.5 rounded-xl border transition-colors ${
            isRecording
              ? 'bg-red-600 text-white border-red-500 animate-pulse'
              : 'bg-[#1C1C1F] text-[#8A8A8E] hover:text-[#2FB083] border-[#232326]'
          }`}
          title={isRecording ? 'Stop & transcribe' : 'Dictate with Gemini audio transcription'}
        >
          {isRecording ? <Square className="w-4 h-4" /> : <Mic className="w-4 h-4" />}
        </button>

        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') handleSend();
          }}
          placeholder={
            isBodyDoubling
              ? 'Tell Lexi what step you are working on right now…'
              : activeTool === 'search'
              ? 'Ask for research or grounding…'
              : activeTool === 'maps'
              ? 'Search for quiet spaces or coffee shops nearby…'
              : 'Ask Lexi for executive function advice…'
          }
          className="flex-1 bg-[#1C1C1F] text-[#F0F0F0] text-sm px-4 py-2.5 rounded-xl border border-[#232326] focus:border-[#2FB083] outline-none"
        />

        <button
          onClick={() => handleSend()}
          disabled={!input.trim() || isGenerating}
          className="p-2.5 bg-[#2FB083] text-[#0C0C0D] rounded-xl disabled:opacity-30 hover:bg-[#2FB083]/90 transition-colors"
          title="Send"
        >
          <Send className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};
