import React, { useState, useRef, useEffect } from 'react';
import {
  Send,
  Mic,
  Square,
  Sparkles,
  Plus,
  Check,
  Globe,
  MapPin,
  Loader2,
  AudioLines,
  AlertCircle,
  RotateCcw,
  XCircle,
  ShieldCheck,
  Link2,
} from 'lucide-react';
import { Task, EnergyLevel } from '../types';
import { useAudioTranscribe } from '../lib/useTranscribe';
import { taskStorage, settingsStorage } from '../lib/storage';
import { redactSensitiveText, sanitizeContextForCloudAi } from '../lib/privacyGate';

interface ChatMessage {
  id: string;
  sender: 'user' | 'lexi';
  text: string;
  timestamp: string;
  suggestedSteps?: SuggestedMicroStep[];
  targetTaskTitle?: string;
  sources?: { title: string; uri: string }[];
  isError?: boolean;
  isConsentRequired?: boolean;
  failedPrompt?: string;
}

export interface SuggestedMicroStep {
  id: string;
  title: string;
  estimatedMinutes: number;
  energy: EnergyLevel;
  accepted?: boolean;
  linkedTaskId?: string;
  linkedTaskTitle?: string;
}

interface LexiChatInterfaceProps {
  tasks?: Task[];
  activeTask?: Task;
  dayMode?: string;
  onTaskCreated?: () => void;
  refresh?: () => void;
  onOpenVoiceMode?: () => void;
  onOpenLiveVoice?: () => void;
  onClose?: () => void;
  embedded?: boolean;
}

// Coordinated client deadline (26s > server 6.5s primary + 14s fallback)
const CLIENT_REQUEST_DEADLINE_MS = 26000;

/**
 * Validates structured breakdown steps returned from the server schema before presenting action cards.
 * Never fabricates steps if validation fails.
 */
export function validateClientBreakdownSteps(
  taskBreakdown: any,
  fallbackTask?: Task
): {
  targetTaskTitle?: string;
  steps: SuggestedMicroStep[];
} {
  if (
    !taskBreakdown ||
    typeof taskBreakdown !== 'object' ||
    !Array.isArray(taskBreakdown.steps) ||
    taskBreakdown.steps.length === 0
  ) {
    return { steps: [] };
  }

  const linkedTaskId =
    (typeof taskBreakdown.targetTaskId === 'string' && taskBreakdown.targetTaskId.trim()) ||
    fallbackTask?.id;
  const linkedTaskTitle =
    (typeof taskBreakdown.targetTaskTitle === 'string' && taskBreakdown.targetTaskTitle.trim()) ||
    fallbackTask?.title ||
    'Task Breakdown';

  const validated: SuggestedMicroStep[] = [];
  const batchTs = Date.now();

  for (let i = 0; i < taskBreakdown.steps.length; i++) {
    const raw = taskBreakdown.steps[i];
    if (!raw || typeof raw !== 'object') continue;
    const title = typeof raw.title === 'string' ? raw.title.trim() : '';
    if (title.length < 3 || title.length > 140) continue;

    const mins = Number(raw.estimatedMinutes);
    const estimatedMinutes = Number.isFinite(mins)
      ? Math.max(1, Math.min(60, Math.round(mins)))
      : 5;

    const rawEnergy = String(raw.energy || 'low').toLowerCase();
    const energy: EnergyLevel =
      rawEnergy === 'high' ? 'high' : rawEnergy === 'medium' ? 'medium' : 'low';

    validated.push({
      id: `step-${batchTs}-${i}`,
      title,
      estimatedMinutes,
      energy,
      accepted: false,
      linkedTaskId,
      linkedTaskTitle,
    });
  }

  return {
    targetTaskTitle: validated.length > 0 ? linkedTaskTitle : undefined,
    steps: validated,
  };
}

export const LexiChatInterface: React.FC<LexiChatInterfaceProps> = ({
  tasks = [],
  activeTask: explicitActiveTask,
  dayMode = 'normal',
  onTaskCreated,
  refresh,
  onOpenVoiceMode,
  onOpenLiveVoice,
}) => {
  const activeTask =
    explicitActiveTask ||
    tasks.find((t) => t.status === 'inProgress') ||
    tasks.find((t) => t.status === 'pending');

  const notifyTasksUpdated = () => {
    if (onTaskCreated) onTaskCreated();
    if (refresh) refresh();
  };

  const handleLaunchVoice = () => {
    if (onOpenLiveVoice) onOpenLiveVoice();
    else if (onOpenVoiceMode) onOpenVoiceMode();
  };
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      id: 'welcome-1',
      sender: 'lexi',
      text: activeTask
        ? `Hey there! I see "${activeTask.title}" is up right now. Would you like me to break it down into tiny 3-minute steps, or help you find a low-energy starting point?`
        : "Hi! I'm Lexi, your executive function companion. Tell me what's on your mind—or paste a messy to-do list and I'll turn it into calm, bite-sized steps.",
      timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
    },
  ]);
  const [inputText, setInputText] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [enableSearch, setEnableSearch] = useState(false);

  const activeRequestIdRef = useRef<number>(0);
  const abortControllerRef = useRef<AbortController | null>(null);
  const acceptedStepIdsRef = useRef<Set<string>>(new Set());

  const { isRecording, isTranscribing, startRecording, stopAndTranscribe } =
    useAudioTranscribe();
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, isLoading]);

  useEffect(() => {
    return () => {
      if (abortControllerRef.current) {
        abortControllerRef.current.abort();
      }
    };
  }, []);

  const handleCancelRequest = () => {
    if (!isLoading) return;
    const cancelledId = activeRequestIdRef.current;
    activeRequestIdRef.current = cancelledId + 1;
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
      abortControllerRef.current = null;
    }
    setIsLoading(false);
    setMessages((prev) => [
      ...prev,
      {
        id: `cancelled-${Date.now()}`,
        sender: 'lexi',
        text: 'Request cancelled. Whenever you are ready, you can retry or send a new message.',
        timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
        isError: true,
      },
    ]);
  };

  const handleEnableCloudAiAndRetry = (promptToRetry?: string, errorMsgId?: string) => {
    settingsStorage.save({ cloudGemini: true });
    if (promptToRetry) {
      handleSend(promptToRetry, { retryErrorMsgId: errorMsgId });
    }
  };

  const handleSend = async (
    overrideText?: string,
    options?: { retryErrorMsgId?: string }
  ) => {
    const textToSend = (overrideText ?? inputText).trim();
    if (!textToSend) return;

    const isRetry = Boolean(options?.retryErrorMsgId);

    // Cancel any previous in-flight request before starting a new one
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
      abortControllerRef.current = null;
    }

    if (!overrideText) {
      setInputText('');
    }

    // Build updated conversation history without duplicating the user message on Retry
    let updatedMessages: ChatMessage[] = [];
    setMessages((prev) => {
      const filtered = options?.retryErrorMsgId
        ? prev.filter((m) => m.id !== options.retryErrorMsgId)
        : [...prev];

      if (isRetry) {
        updatedMessages = filtered;
        return filtered;
      }

      const userMsg: ChatMessage = {
        id: `user-${Date.now()}`,
        sender: 'user',
        text: textToSend,
        timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
      };
      updatedMessages = [...filtered, userMsg];
      return updatedMessages;
    });

    // Check Cloud AI consent setting
    const currentSettings = settingsStorage.get();
    if (!currentSettings.cloudGemini) {
      setMessages((prev) => [
        ...prev,
        {
          id: `consent-${Date.now()}`,
          sender: 'lexi',
          text: 'Cloud AI is currently turned off in your Privacy Settings. Enable Cloud Gemini to chat with Lexi or generate task breakdowns.',
          timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
          isError: true,
          isConsentRequired: true,
          failedPrompt: textToSend,
        },
      ]);
      return;
    }

    const reqNumber = activeRequestIdRef.current + 1;
    activeRequestIdRef.current = reqNumber;
    const correlationId = `chat-${reqNumber}-${Date.now()}`;

    const controller = new AbortController();
    abortControllerRef.current = controller;
    setIsLoading(true);

    const timeoutId = setTimeout(() => {
      controller.abort(new Error('CLIENT_DEADLINE_EXCEEDED'));
    }, CLIENT_REQUEST_DEADLINE_MS);

    try {
      // Construct history cleanly from current messages + current prompt if needed
      const historySource =
        updatedMessages.length > 0
          ? updatedMessages
          : [
              ...messages.filter((m) => m.id !== options?.retryErrorMsgId),
              ...(isRetry
                ? []
                : [
                    {
                      id: `user-${Date.now()}`,
                      sender: 'user' as const,
                      text: textToSend,
                      timestamp: '',
                    },
                  ]),
            ];

      const cleanHistory = historySource
        .filter((m) => !m.isError && !m.isConsentRequired && m.text.trim().length > 0)
        .slice(-10)
        .map((m) => ({
          sender: m.sender,
          text: redactSensitiveText(m.text).sanitizedText,
        }));

      const safeContext = sanitizeContextForCloudAi({
        activeTask: activeTask ? activeTask.title : 'None',
        activeTaskId: activeTask?.id,
        activeTaskTitle: activeTask?.title,
        dayMode,
      });

      const res = await fetch('/api/gemini/chat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-request-id': correlationId,
          'x-cloud-ai-consent': String(currentSettings.cloudGemini),
          'x-neuroflow-client': 'web-applet-v1',
        },
        signal: controller.signal,
        body: JSON.stringify({
          requestId: correlationId,
          messages: cleanHistory,
          enableSearch,
          context: safeContext,
        }),
      });

      clearTimeout(timeoutId);

      if (activeRequestIdRef.current !== reqNumber) {
        return;
      }

      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        if (data?.code === 'CLOUD_AI_DISABLED') {
          setMessages((prev) => [
            ...prev,
            {
              id: `consent-${Date.now()}`,
              sender: 'lexi',
              text: data.error || 'Cloud AI is disabled in Settings.',
              timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
              isError: true,
              isConsentRequired: true,
              failedPrompt: textToSend,
            },
          ]);
          return;
        }
        throw new Error(data.error || `Request failed with status ${res.status}`);
      }

      const replyText: string =
        typeof data.reply === 'string' && data.reply.trim()
          ? data.reply.trim()
          : "I'm here with you. Tell me which step feels easiest to start.";

      // Validate structured task breakdown from server schema before presenting action cards
      const validatedBreakdown = validateClientBreakdownSteps(data.taskBreakdown, activeTask);

      const lexiMsg: ChatMessage = {
        id: `lexi-${Date.now()}`,
        sender: 'lexi',
        text: replyText,
        timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
        suggestedSteps: validatedBreakdown.steps.length > 0 ? validatedBreakdown.steps : undefined,
        targetTaskTitle: validatedBreakdown.targetTaskTitle,
        sources: Array.isArray(data.sources) ? data.sources : undefined,
      };

      setMessages((prev) => [...prev, lexiMsg]);
    } catch (err: any) {
      clearTimeout(timeoutId);

      if (activeRequestIdRef.current !== reqNumber) {
        return;
      }

      const isTimeout =
        err?.name === 'AbortError' ||
        String(err?.message || '').includes('DEADLINE_EXCEEDED') ||
        String(err?.message || '').includes('timed out');

      const friendlyError = isTimeout
        ? 'Lexi took too long to respond (request timed out). Your message was saved—tap Retry to try again.'
        : `Couldn't complete response (${err?.message || 'connection error'}). Tap Retry to try again.`;

      setMessages((prev) => [
        ...prev,
        {
          id: `err-${Date.now()}`,
          sender: 'lexi',
          text: friendlyError,
          timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
          isError: true,
          failedPrompt: textToSend,
        },
      ]);
    } finally {
      if (activeRequestIdRef.current === reqNumber) {
        setIsLoading(false);
        abortControllerRef.current = null;
      }
    }
  };

  const handleFindNearbyPlaces = async () => {
    const query =
      inputText.trim() || 'Quiet coffee shops or libraries nearby for focused work';
    if (!inputText.trim()) {
      setInputText('');
    }

    const userMsg: ChatMessage = {
      id: `user-maps-${Date.now()}`,
      sender: 'user',
      text: `📍 Find nearby: ${query}`,
      timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
    };

    setMessages((prev) => [...prev, userMsg]);

    const currentSettings = settingsStorage.get();
    if (!currentSettings.cloudGemini) {
      setMessages((prev) => [
        ...prev,
        {
          id: `consent-maps-${Date.now()}`,
          sender: 'lexi',
          text: 'Cloud AI is currently turned off in your Privacy Settings. Enable Cloud Gemini to search nearby places.',
          timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
          isError: true,
          isConsentRequired: true,
          failedPrompt: query,
        },
      ]);
      return;
    }

    const reqNumber = activeRequestIdRef.current + 1;
    activeRequestIdRef.current = reqNumber;
    const controller = new AbortController();
    abortControllerRef.current = controller;
    setIsLoading(true);

    const timeoutId = setTimeout(() => {
      controller.abort(new Error('CLIENT_DEADLINE_EXCEEDED'));
    }, CLIENT_REQUEST_DEADLINE_MS);

    try {
      const res = await fetch('/api/gemini/maps', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-request-id': `maps-${reqNumber}-${Date.now()}`,
          'x-cloud-ai-consent': String(currentSettings.cloudGemini),
          'x-neuroflow-client': 'web-applet-v1',
        },
        signal: controller.signal,
        body: JSON.stringify({ query: redactSensitiveText(query).sanitizedText }),
      });

      clearTimeout(timeoutId);
      if (activeRequestIdRef.current !== reqNumber) return;

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error || 'Maps search failed');

      setMessages((prev) => [
        ...prev,
        {
          id: `lexi-maps-${Date.now()}`,
          sender: 'lexi',
          text: data.reply || 'Here are some nearby options:',
          timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
          sources: data.places,
        },
      ]);
    } catch (err: any) {
      clearTimeout(timeoutId);
      if (activeRequestIdRef.current !== reqNumber) return;
      setMessages((prev) => [
        ...prev,
        {
          id: `err-maps-${Date.now()}`,
          sender: 'lexi',
          text: `Couldn't fetch nearby places right now (${err?.message || 'error'}).`,
          timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
          isError: true,
          failedPrompt: query,
        },
      ]);
    } finally {
      if (activeRequestIdRef.current === reqNumber) {
        setIsLoading(false);
        abortControllerRef.current = null;
      }
    }
  };

  const handleAcceptStep = (msgId: string, step: SuggestedMicroStep) => {
    // Idempotency guard: prevent duplicate task creation if clicked multiple times
    if (step.accepted || acceptedStepIdsRef.current.has(step.id)) {
      return;
    }
    acceptedStepIdsRef.current.add(step.id);

    const parentContextNote = step.linkedTaskTitle
      ? `Micro-step for "${step.linkedTaskTitle}" (${step.estimatedMinutes}m)`
      : `Suggested by Lexi (${step.estimatedMinutes}m micro-step)`;

    const newTask: Task = {
      id: `task-lexi-${step.id}`,
      title: step.title,
      notes: parentContextNote,
      energy: step.energy,
      status: 'pending',
      createdAt: new Date().toISOString(),
      estimatedMinutes: step.estimatedMinutes,
      isQuickWin: step.estimatedMinutes <= 10 || step.energy === 'low',
    };

    taskStorage.save(newTask);

    // If linked to an existing parent task in storage, also record the step on the parent task's notes
    if (step.linkedTaskId) {
      const existingTasks = taskStorage.getAll();
      const parentTask = existingTasks.find((t) => t.id === step.linkedTaskId);
      if (parentTask) {
        const stepBullet = `- [ ] ${step.title} (${step.estimatedMinutes}m)`;
        const updatedNotes = parentTask.notes
          ? parentTask.notes.includes(step.title)
            ? parentTask.notes
            : `${parentTask.notes}\n${stepBullet}`
          : `Breakdown steps:\n${stepBullet}`;
        taskStorage.save({ ...parentTask, notes: updatedNotes });
      }
    }

    notifyTasksUpdated();

    setMessages((prev) =>
      prev.map((m) => {
        if (m.id !== msgId || !m.suggestedSteps) return m;
        return {
          ...m,
          suggestedSteps: m.suggestedSteps.map((s) =>
            s.id === step.id ? { ...s, accepted: true } : s
          ),
        };
      })
    );
  };

  const handleMicToggle = async () => {
    if (isRecording) {
      const transcript = await stopAndTranscribe();
      if (transcript) {
        setInputText((prev) => (prev ? `${prev} ${transcript}` : transcript));
      }
    } else {
      await startRecording();
    }
  };

  const quickPrompts = [
    'Break down my current task into 3 tiny steps',
    'I feel stuck and overwhelmed—what is 1 easy win?',
    'Help me plan a 10-minute reset routine',
  ];

  return (
    <div className="flex flex-col h-[calc(100vh-8.5rem)] max-w-2xl mx-auto px-4 pt-3">
      {/* Top Bar with Live Voice CTA & Grounding Toggles */}
      <div className="flex items-center justify-between gap-2 pb-3 mb-2 border-b border-[#232326]">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-xl bg-[#2FB083]/15 border border-[#2FB083]/30 flex items-center justify-center text-[#2FB083]">
            <Sparkles className="w-4 h-4" />
          </div>
          <div>
            <h2 className="text-sm font-semibold text-[#F0F0F0] flex items-center gap-1.5">
              <span>Lexi Companion</span>
              <span className="inline-flex items-center gap-1 text-[10px] font-normal text-[#8A8A8E] bg-[#1C1C1F] px-2 py-0.5 rounded-md border border-[#232326]">
                <ShieldCheck className="w-3 h-3 text-[#2FB083]" />
                Privacy Gate Active
              </span>
            </h2>
            <p className="text-[11px] text-[#8A8A8E]">
              Task breakdown, gentle pacing & zero-guilt recovery
            </p>
          </div>
        </div>

        <div className="flex items-center gap-1.5">
          <button
            type="button"
            onClick={() => setEnableSearch(!enableSearch)}
            title="Toggle Google Search Grounding for current facts"
            className={`flex items-center gap-1 px-2.5 py-1.5 rounded-xl text-xs font-medium border transition-all ${
              enableSearch
                ? 'bg-[#5B8DEF]/15 text-[#5B8DEF] border-[#5B8DEF]/40'
                : 'bg-[#161618] text-[#8A8A8E] border-[#232326] hover:text-[#F0F0F0]'
            }`}
          >
            <Globe className="w-3.5 h-3.5" />
            <span className="hidden sm:inline">Web Search</span>
          </button>

          <button
            type="button"
            onClick={handleLaunchVoice}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold bg-[#2FB083] text-[#0C0C0D] hover:bg-[#2FB083]/90 transition-all shadow-sm"
          >
            <AudioLines className="w-3.5 h-3.5" />
            <span>Live Voice</span>
          </button>
        </div>
      </div>

      {/* Quick Prompts Row */}
      <div className="flex items-center gap-2 overflow-x-auto no-scrollbar pb-2 mb-1">
        {quickPrompts.map((prompt, idx) => (
          <button
            key={idx}
            type="button"
            disabled={isLoading}
            onClick={() => handleSend(prompt)}
            className="shrink-0 text-xs bg-[#161618] hover:bg-[#1C1C1F] disabled:opacity-50 text-[#8A8A8E] hover:text-[#F0F0F0] border border-[#232326] px-3 py-1.5 rounded-xl transition-colors"
          >
            {prompt}
          </button>
        ))}
      </div>

      {/* Chat Messages Scroll Area */}
      <div className="flex-1 overflow-y-auto space-y-4 pr-1 py-2">
        {messages.map((msg) => (
          <div
            key={msg.id}
            className={`flex flex-col ${
              msg.sender === 'user' ? 'items-end' : 'items-start'
            }`}
          >
            <div
              className={`max-w-[85%] rounded-2xl px-4 py-3 text-sm leading-relaxed ${
                msg.sender === 'user'
                  ? 'bg-[#2FB083] text-[#0C0C0D] font-medium rounded-br-xs'
                  : msg.isError
                  ? 'bg-[#D9A441]/10 text-[#F0F0F0] border border-[#D9A441]/40 rounded-bl-xs'
                  : 'bg-[#161618] text-[#F0F0F0] border border-[#232326] rounded-bl-xs'
              }`}
            >
              <div className="whitespace-pre-wrap">{msg.text}</div>

              {/* Error / Consent Action Bar */}
              {msg.isError && (
                <div className="mt-3 pt-2.5 border-t border-[#232326] flex flex-wrap items-center gap-2">
                  {msg.isConsentRequired ? (
                    <button
                      type="button"
                      onClick={() => handleEnableCloudAiAndRetry(msg.failedPrompt, msg.id)}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold bg-[#2FB083] text-[#0C0C0D] hover:bg-[#2FB083]/90 transition-colors"
                    >
                      <Sparkles className="w-3.5 h-3.5" />
                      <span>Enable Cloud AI & Retry</span>
                    </button>
                  ) : (
                    msg.failedPrompt && (
                      <button
                        type="button"
                        disabled={isLoading}
                        onClick={() => handleSend(msg.failedPrompt, { retryErrorMsgId: msg.id })}
                        className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold bg-[#212124] text-[#F0F0F0] hover:bg-[#2C2C30] border border-[#232326] transition-colors disabled:opacity-50"
                      >
                        <RotateCcw className="w-3.5 h-3.5 text-[#2FB083]" />
                        <span>Retry</span>
                      </button>
                    )
                  )}
                </div>
              )}

              {/* Grounding Sources / Places */}
              {msg.sources && msg.sources.length > 0 && (
                <div className="mt-3 pt-2.5 border-t border-[#232326] flex flex-wrap gap-1.5">
                  {msg.sources.map((src, i) => (
                    <a
                      key={i}
                      href={src.uri}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="inline-flex items-center gap-1 text-[11px] bg-[#212124] hover:bg-[#28282C] text-[#5B8DEF] px-2.5 py-1 rounded-lg border border-[#232326] transition-colors"
                    >
                      <Globe className="w-3 h-3" />
                      <span className="truncate max-w-[180px]">{src.title}</span>
                    </a>
                  ))}
                </div>
              )}
            </div>

            {/* Validated Actionable Micro-Step Cards */}
            {msg.suggestedSteps && msg.suggestedSteps.length > 0 && (
              <div className="mt-2.5 w-full max-w-[85%] bg-[#161618] border border-[#232326] rounded-2xl p-3 space-y-2 shadow-lg">
                <div className="flex items-center justify-between px-1 gap-2">
                  <span className="text-[11px] font-semibold uppercase tracking-wider text-[#2FB083]">
                    Suggested Micro-Steps (Tap to Add)
                  </span>
                  {msg.targetTaskTitle && (
                    <span className="inline-flex items-center gap-1 text-[11px] text-[#8A8A8E] bg-[#1C1C1F] px-2 py-0.5 rounded-lg border border-[#232326] truncate max-w-[180px]">
                      <Link2 className="w-3 h-3 text-[#2FB083] shrink-0" />
                      <span className="truncate">{msg.targetTaskTitle}</span>
                    </span>
                  )}
                </div>

                {msg.suggestedSteps.map((step) => (
                  <div
                    key={step.id}
                    className="flex items-center justify-between gap-3 p-2.5 rounded-xl bg-[#1C1C1F] border border-[#232326]"
                  >
                    <div className="min-w-0 flex-1">
                      <p className="text-xs font-medium text-[#F0F0F0] leading-snug">
                        {step.title}
                      </p>
                      <span className="text-[10px] text-[#8A8A8E]">
                        ~{step.estimatedMinutes} min · {step.energy} energy
                      </span>
                    </div>

                    <button
                      type="button"
                      disabled={step.accepted}
                      onClick={() => handleAcceptStep(msg.id, step)}
                      className={`shrink-0 flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs font-medium transition-all ${
                        step.accepted
                          ? 'bg-[#2FB083]/20 text-[#2FB083] cursor-default'
                          : 'bg-[#2FB083] text-[#0C0C0D] hover:bg-[#2FB083]/90'
                      }`}
                    >
                      {step.accepted ? (
                        <>
                          <Check className="w-3.5 h-3.5" />
                          <span>Added</span>
                        </>
                      ) : (
                        <>
                          <Plus className="w-3.5 h-3.5" />
                          <span>Add</span>
                        </>
                      )}
                    </button>
                  </div>
                ))}
              </div>
            )}

            <span className="text-[10px] text-[#555559] mt-1 px-1">{msg.timestamp}</span>
          </div>
        ))}

        {isLoading && (
          <div className="flex items-center justify-between gap-3 text-xs text-[#8A8A8E] bg-[#161618] border border-[#232326] w-fit rounded-2xl px-4 py-3">
            <div className="flex items-center gap-2">
              <Loader2 className="w-4 h-4 text-[#2FB083] animate-spin" />
              <span>Lexi is thinking...</span>
            </div>
            <button
              type="button"
              onClick={handleCancelRequest}
              className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg text-[11px] font-medium bg-[#212124] hover:bg-[#2C2C30] text-[#F0F0F0] border border-[#232326] transition-colors"
            >
              <XCircle className="w-3.5 h-3.5 text-[#D9A441]" />
              <span>Cancel</span>
            </button>
          </div>
        )}

        <div ref={bottomRef} />
      </div>

      {/* Bottom Input Composer */}
      <div className="pt-2 pb-4">
        <div className="flex items-center gap-2 bg-[#161618] border border-[#232326] focus-within:border-[#2FB083]/60 rounded-2xl p-2 shadow-lg">
          <button
            type="button"
            onClick={handleMicToggle}
            disabled={isTranscribing}
            title={isRecording ? 'Stop & Transcribe' : 'Dictate with Gemini Audio'}
            className={`p-2.5 rounded-xl transition-all shrink-0 ${
              isRecording
                ? 'bg-[#D9A441] text-[#0C0C0D] animate-pulse'
                : 'bg-[#212124] text-[#8A8A8E] hover:text-[#F0F0F0]'
            }`}
          >
            {isTranscribing ? (
              <Loader2 className="w-4 h-4 animate-spin text-[#2FB083]" />
            ) : isRecording ? (
              <Square className="w-4 h-4 fill-current" />
            ) : (
              <Mic className="w-4 h-4" />
            )}
          </button>

          <button
            type="button"
            onClick={handleFindNearbyPlaces}
            disabled={isLoading}
            title="Find quiet study spots or errands nearby with Google Maps Grounding"
            className="p-2.5 rounded-xl bg-[#212124] text-[#8A8A8E] hover:text-[#2FB083] transition-colors shrink-0 disabled:opacity-40"
          >
            <MapPin className="w-4 h-4" />
          </button>

          <input
            type="text"
            value={inputText}
            onChange={(e) => setInputText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                handleSend();
              }
            }}
            placeholder={
              isRecording
                ? 'Listening... tap square when done'
                : 'Ask Lexi to break down a task or chat...'
            }
            className="flex-1 bg-transparent text-sm text-[#F0F0F0] placeholder-[#555559] focus:outline-none px-1"
          />

          <button
            type="button"
            onClick={() => handleSend()}
            disabled={!inputText.trim() || isLoading}
            className="p-2.5 rounded-xl bg-[#2FB083] text-[#0C0C0D] disabled:opacity-30 hover:bg-[#2FB083]/90 transition-all shrink-0"
          >
            <Send className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  );
};
