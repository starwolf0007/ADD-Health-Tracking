import { cloudFetch, requireCloudConsent } from '../lib/cloudClient';
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
  ChevronRight,
} from 'lucide-react';
import { Task, LexiProposal } from '../types';
import { LexiAvatar } from './LexiAvatar';
import { taskStorage } from '../lib/storage';
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

export interface ChatMessage {
  id: string;
  sender: 'lexi' | 'user';
  text: string;
  modelUsed?: string;
  proposal?: LexiProposal;
  suggestedTask?: {
    title: string;
    energy: 'low' | 'medium' | 'high';
    estimatedMinutes: number;
  };
  sources?: GroundingSource[];
  places?: GroundingPlace[];
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
  const activeTask =
    tasks.find((t) => t.status === 'inProgress') || pendingTasks[0] || null;

  const [input, setInput] = useState('');
  const [selectedModel, setSelectedModel] = useState<
    'gemini-3.8-flash' | 'gemini-4-argon' | 'gemini-3.1-flash-lite'
  >('gemini-3.8-flash');
  const [activeTool, setActiveTool] = useState<'none' | 'search' | 'maps'>(
    'none',
  );
  const [isGenerating, setIsGenerating] = useState(false);

  const [messages, setMessages] = useState<ChatMessage[]>(() => [
    {
      id: 'lexi-welcome',
      sender: 'lexi',
      text: activeTask
        ? `Hey! I'm Lexi, your executive function coach. Right now, your active focus is "${activeTask.title}".\n\nNeed advice breaking it down, overcoming inertia, or reorganizing your day? Choose an advice prompt below or type what's on your mind.`
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

  const [appliedActions, setAppliedActions] = useState<Record<string, boolean>>(
    {},
  );
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Audio transcription hook (gemini-3.5-transcribe)
  const {
    isRecording,
    isTranscribing,
    startRecording,
    stopAndTranscribe,
    error: recordingError,
  } = useAudioTranscribe();

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages, isGenerating]);

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

  const handleSend = async (
    textToSend?: string,
    forcedModel?: string,
    forcedTool?: string,
  ) => {
    const text = (textToSend || input).trim();
    if (!text || isGenerating) return;

    try {
      requireCloudConsent();
    } catch (error) {
      setMessages((prev) => [
        ...prev,
        {
          id: `error-${Date.now()}`,
          sender: 'lexi',
          text: (error as Error).message,
        },
      ]);
      return;
    }
    const userMsg: ChatMessage = {
      id: `user-${Date.now()}`,
      sender: 'user',
      text,
    };

    setMessages((prev) => [...prev, userMsg]);
    if (!textToSend) setInput('');
    setIsGenerating(true);

    const modelToUse = forcedModel || selectedModel;
    const toolToUse = forcedTool || activeTool;

    try {
      if (toolToUse === 'search') {
        // Search Grounding route (gemini-3.8-flash + googleSearch)
        const res = await cloudFetch('/api/gemini/search', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ query: text }),
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
              navigator.geolocation.getCurrentPosition(res, rej, {
                timeout: 3000,
              }),
            );
            lat = pos.coords.latitude;
            lng = pos.coords.longitude;
          }
        } catch {}

        const res = await cloudFetch('/api/gemini/maps', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            query: text,
            latitude: lat,
            longitude: lng,
          }),
        });
        const data = await res.json();
        if (data.error) throw new Error(data.error);

        setMessages((prev) => [
          ...prev,
          {
            id: `lexi-${Date.now()}`,
            sender: 'lexi',
            text:
              data.text ||
              'Here are sensory-friendly and quiet places near you.',
            modelUsed: 'gemini-3.8-flash (Maps Grounded)',
            places: data.places || [],
          },
        ]);
      } else {
        // Multi-Turn Executive Function Chat route
        const executiveSystemPrompt = `You are Lexi, an empathetic, non-judgmental ADHD executive function coach.
Your primary goals:
1. Provide practical, highly specific executive function advice (e.g. task initiation, working memory offloading, body doubling, time blindness management, cognitive friction reduction).
2. Deconstruct overwhelming goals into tiny, concrete first physical steps that take under 2 minutes.
3. If the user asks to break down a task, give 3 bullet points with a clear, small first step.
4. Keep the tone warm, validating, and direct. Never moralize or induce shame for unfinished tasks.
5. Format your response cleanly with clear spacing.`;

        const history = [...messages, userMsg].map((m) => ({
          role: m.sender === 'user' ? 'user' : 'assistant',
          content: m.text,
        }));

        const res = await cloudFetch('/api/gemini/chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            messages: history,
            model: modelToUse,
            systemInstruction: executiveSystemPrompt,
          }),
        });
        const data = await res.json();
        if (data.error) throw new Error(data.error);

        setMessages((prev) => [
          ...prev,
          {
            id: `lexi-${Date.now()}`,
            sender: 'lexi',
            text:
              data.reply ||
              'I am right here with you. What feels like the least resistant step?',
            modelUsed: data.model,
          },
        ]);
      }
    } catch (err: any) {
      console.error('Lexi chat error:', err);
      setMessages((prev) => [
        ...prev,
        {
          id: `lexi-${Date.now()}`,
          sender: 'lexi',
          text: `I had trouble connecting: ${err.message}. Let me know if you would like to try again.`,
        },
      ]);
    } finally {
      setIsGenerating(false);
    }
  };

  const handleAddTaskToToday = (
    msgId: string,
    taskInfo: {
      title: string;
      energy: 'low' | 'medium' | 'high';
      estimatedMinutes: number;
    },
  ) => {
    const newTask: Task = {
      id: `task-${Date.now()}`,
      title: taskInfo.title,
      energy: taskInfo.energy,
      status: 'pending',
      createdAt: new Date().toISOString(),
      estimatedMinutes: taskInfo.estimatedMinutes,
      isQuickWin: taskInfo.energy === 'low',
    };

    taskStorage.save(newTask);
    setAppliedActions((prev) => ({ ...prev, [msgId]: true }));
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
        proposal.payload.nextAction || 'Open task to resume',
      );
    }

    setAppliedActions((prev) => ({ ...prev, [msgId]: true }));
    refresh();
  };

  return (
    <div
      className={`flex flex-col bg-[#0C0C0D] text-[#F0F0F0] ${
        embedded ? 'h-[calc(100vh-140px)]' : 'h-full'
      }`}
    >
      {/* Top Header Card */}
      <div className="p-4 border-b border-[#232326] bg-[#161618] flex items-center justify-between">
        <div className="flex items-center gap-3">
          <LexiAvatar
            size={42}
            visualState={isGenerating ? 'thinking' : 'idle'}
          />
          <div>
            <div className="flex items-center gap-1.5">
              <h2 className="text-base font-semibold text-[#F0F0F0]">
                Lexi AI
              </h2>
              <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-[#BB86FC]/15 text-[#BB86FC] border border-[#BB86FC]/30">
                Coach
              </span>
            </div>
            <p className="text-xs text-[#8A8A8E]">
              ADHD Executive Function & Task Initiation
            </p>
          </div>
        </div>

        {onOpenLiveVoice && (
          <button
            onClick={onOpenLiveVoice}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#BB86FC]/15 hover:bg-[#BB86FC]/25 text-[#BB86FC] text-xs font-semibold border border-[#BB86FC]/30 shadow-sm transition-all"
            title="Start real-time voice conversation"
          >
            <Radio className="w-3.5 h-3.5 animate-pulse" />
            <span>Live Voice</span>
          </button>
        )}
      </div>

      {/* Advice Presets Carousel */}
      <div className="px-4 py-2.5 bg-[#121214] border-b border-[#232326] overflow-x-auto no-scrollbar flex items-center gap-2">
        <button
          onClick={() => {
            setSelectedModel('gemini-4-argon');
            setActiveTool('none');
            handleSend(
              'I have a task that feels way too big and overwhelming. Can you help me break it down into 3 tiny physical steps that take under 2 minutes each?',
              'gemini-4-argon',
              'none',
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
              'none',
            );
          }}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#1C1C1F] hover:bg-[#232326] text-xs text-[#F0F0F0] border border-[#232326] whitespace-nowrap transition-colors"
        >
          <Zap className="w-3.5 h-3.5 text-[#2FB083]" />
          <span>Break task paralysis</span>
        </button>

        <button
          onClick={() => {
            setSelectedModel('gemini-3.1-flash-lite');
            setActiveTool('none');
            handleSend(
              'My energy is completely depleted today. How do I pivot my schedule so I do not feel guilty?',
              'gemini-3.1-flash-lite',
              'none',
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
              'maps',
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
              'search',
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
            <option value="gemini-3.8-flash">
              gemini-3.8-flash (Balanced)
            </option>
            <option value="gemini-4-argon">
              gemini-4-argon (Deep Planning)
            </option>
            <option value="gemini-3.1-flash-lite">
              gemini-3.1-flash-lite (Instant)
            </option>
          </select>
        </div>

        {/* Tool Grounding Toggles */}
        <div className="flex items-center gap-1.5">
          <button
            onClick={() =>
              setActiveTool(activeTool === 'search' ? 'none' : 'search')
            }
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
            onClick={() =>
              setActiveTool(activeTool === 'maps' ? 'none' : 'maps')
            }
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
                        <span className="truncate max-w-[150px]">
                          {src.title || src.uri}
                        </span>
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
                        <span className="font-medium truncate">
                          {place.title}
                        </span>
                        <div className="flex items-center gap-1 text-[11px] text-[#7AA7A0] shrink-0 ml-2">
                          <span>Open Maps</span>
                          <ExternalLink className="w-3 h-3" />
                        </div>
                      </a>
                    ))}
                  </div>
                </div>
              )}

              {msg.modelUsed && (
                <span className="block text-[10px] text-[#555559] mt-2 font-mono">
                  {msg.modelUsed}
                </span>
              )}
            </div>

            {/* Quick-Add Action: Micro-Task Proposal */}
            {msg.suggestedTask && (
              <div className="mt-2 max-w-[88%] bg-[#1A1A1D] border border-[#2FB083]/40 rounded-xl p-3 shadow-md">
                <div className="flex items-center justify-between mb-1.5">
                  <div className="flex items-center gap-1.5 text-[11px] font-semibold text-[#2FB083] uppercase">
                    <Plus className="w-3.5 h-3.5" />
                    <span>Suggested Action Step</span>
                  </div>
                  <span className="text-[10px] px-1.5 py-0.5 rounded bg-[#2FB083]/15 text-[#2FB083] font-mono">
                    ~{msg.suggestedTask.estimatedMinutes} min
                  </span>
                </div>

                <p className="text-xs text-[#F0F0F0] mb-2 font-medium">
                  {msg.suggestedTask.title}
                </p>

                {appliedActions[msg.id] ? (
                  <div className="flex items-center gap-1.5 text-xs text-[#2FB083] font-medium">
                    <Check className="w-4 h-4" />
                    <span>Added to Today's Tasks</span>
                  </div>
                ) : (
                  <button
                    onClick={() =>
                      handleAddTaskToToday(msg.id, msg.suggestedTask!)
                    }
                    className="flex items-center gap-1.5 px-3 py-1.5 bg-[#2FB083] text-[#0C0C0D] rounded-lg text-xs font-semibold hover:bg-[#2FB083]/90 transition-colors"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    <span>Add this step to Today</span>
                  </button>
                )}
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
                      onClick={() =>
                        handleConfirmProposal(msg.id, msg.proposal!)
                      }
                      className="px-3 py-1.5 bg-[#2FB083] text-[#0C0C0D] rounded-lg text-xs font-semibold hover:bg-[#2FB083]/90 transition-colors"
                    >
                      Start Now
                    </button>
                    <button
                      onClick={() =>
                        setAppliedActions((prev) => ({
                          ...prev,
                          [msg.id]: true,
                        }))
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
          <div className="flex items-center gap-2 text-xs text-[#8A8A8E] py-2 animate-pulse">
            <Loader2 className="w-3.5 h-3.5 animate-spin text-[#2FB083]" />
            <span>Lexi is formulating executive advice…</span>
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

      {recordingError && (
        <p role="alert" className="px-4 py-2 text-xs text-red-300">
          {recordingError}
        </p>
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
          title={
            isRecording
              ? 'Stop & transcribe'
              : 'Dictate with Gemini audio transcription'
          }
        >
          {isRecording ? (
            <Square className="w-4 h-4" />
          ) : (
            <Mic className="w-4 h-4" />
          )}
        </button>

        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') handleSend();
          }}
          placeholder={
            activeTool === 'search'
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
