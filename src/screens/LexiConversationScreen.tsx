import { cloudFetch, requireCloudConsent } from '../lib/cloudClient';
import React, { useState, useRef, useEffect } from 'react';
import {
  ArrowLeft,
  Sparkles,
  Send,
  Check,
  Globe,
  MapPin,
  Mic,
  Square,
  Radio,
  ExternalLink,
  ChevronDown,
  Loader2,
} from 'lucide-react';
import { Task, LexiProposal } from '../types';
import { LexiAvatar } from '../components/LexiAvatar';
import { taskStorage } from '../lib/storage';
import { useAudioTranscribe } from '../lib/useTranscribe';

interface LexiConversationScreenProps {
  tasks: Task[];
  onBack: () => void;
  onOpenLiveVoice: () => void;
  refresh: () => void;
}

interface GroundingSource {
  uri: string;
  title: string;
}

interface GroundingPlace {
  title: string;
  uri: string;
  placeAnswerSources?: any;
}

interface ChatMessage {
  id: string;
  sender: 'lexi' | 'user';
  text: string;
  modelUsed?: string;
  proposal?: LexiProposal;
  sources?: GroundingSource[];
  places?: GroundingPlace[];
}

export const LexiConversationScreen: React.FC<LexiConversationScreenProps> = ({
  tasks,
  onBack,
  onOpenLiveVoice,
  refresh,
}) => {
  const pendingTasks = tasks.filter((t) => t.status !== 'completed');
  const recommendedTask = pendingTasks[0] || null;

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
      id: 'msg-init',
      sender: 'lexi',
      text: recommendedTask
        ? `Hey. I took a look at your day. We have "${recommendedTask.title}" ready. How's your energy right now?`
        : 'Hey. Your day is currently clear. Want to talk through your focus, search for advice, or explore quiet places nearby?',
      proposal: recommendedTask
        ? {
            type: 'start_task',
            payload: { taskId: recommendedTask.id },
            requiresConfirmation: true,
            confirmationPrompt: `Start "${recommendedTask.title}"?`,
          }
        : undefined,
    },
  ]);

  const [appliedProposals, setAppliedProposals] = useState<
    Record<string, boolean>
  >({});
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

  const handleSend = async (textToSend?: string) => {
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

    try {
      if (activeTool === 'search') {
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
            text: data.text || 'Here is what I found.',
            modelUsed: 'gemini-3.8-flash (Search Grounded)',
            sources: data.sources || [],
          },
        ]);
      } else if (activeTool === 'maps') {
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
            text: data.text || 'Here are some places that fit your request.',
            modelUsed: 'gemini-3.8-flash (Maps Grounded)',
            places: data.places || [],
          },
        ]);
      } else {
        // Multi-Turn Chat route with selected model
        const history = [...messages, userMsg].map((m) => ({
          role: m.sender === 'user' ? 'user' : 'assistant',
          content: m.text,
        }));

        const res = await cloudFetch('/api/gemini/chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            messages: history,
            model: selectedModel,
          }),
        });
        const data = await res.json();
        if (data.error) throw new Error(data.error);

        let newProposal: LexiProposal | undefined = undefined;
        const lower = text.toLowerCase();
        if (
          recommendedTask &&
          (lower.includes('start') || lower.includes('ready'))
        ) {
          newProposal = {
            type: 'start_task',
            payload: { taskId: recommendedTask.id },
            requiresConfirmation: true,
            confirmationPrompt: `Start "${recommendedTask.title}" now?`,
          };
        } else if (
          recommendedTask &&
          (lower.includes('stuck') || lower.includes('pause'))
        ) {
          newProposal = {
            type: 'create_reentry_note',
            payload: {
              taskId: recommendedTask.id,
              nextAction: 'Open the item and review the top section.',
            },
            requiresConfirmation: true,
            confirmationPrompt: `Save return point and pause "${recommendedTask.title}"?`,
          };
        }

        setMessages((prev) => [
          ...prev,
          {
            id: `lexi-${Date.now()}`,
            sender: 'lexi',
            text:
              data.reply ||
              'I hear you. Let me know what step you want to take next.',
            modelUsed: data.model,
            proposal: newProposal,
          },
        ]);
      }
    } catch (err: any) {
      console.error('Chat error:', err);
      setMessages((prev) => [
        ...prev,
        {
          id: `lexi-${Date.now()}`,
          sender: 'lexi',
          text: `I had trouble connecting to the network: ${err.message}. Let me know if you want to retry.`,
        },
      ]);
    } finally {
      setIsGenerating(false);
    }
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

    setAppliedProposals((prev) => ({ ...prev, [msgId]: true }));
    refresh();
  };

  return (
    <div className="fixed inset-0 z-50 bg-[#0C0C0D] flex flex-col max-w-2xl mx-auto shadow-2xl">
      {/* Header */}
      <div className="p-3.5 flex items-center justify-between border-b border-[#232326] bg-[#161618]">
        <div className="flex items-center gap-3">
          <button
            onClick={onBack}
            className="p-1.5 text-[#8A8A8E] hover:text-[#F0F0F0] rounded-xl"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <LexiAvatar size={36} visualState="thinking" />
          <div>
            <h3 className="text-sm font-medium text-[#F0F0F0]">
              Lexi Companion
            </h3>
            <p className="text-[11px] text-[#2FB083]">
              ADHD Executive Function AI
            </p>
          </div>
        </div>

        {/* Live Voice CTA button */}
        <button
          onClick={onOpenLiveVoice}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#BB86FC]/15 hover:bg-[#BB86FC]/25 text-[#BB86FC] text-xs font-semibold border border-[#BB86FC]/30 shadow-sm transition-all"
        >
          <Radio className="w-3.5 h-3.5 animate-pulse" />
          <span>Live Voice</span>
        </button>
      </div>

      {/* Model & Tool Toolbar */}
      <div className="px-3 py-2 bg-[#1C1C1F] border-b border-[#232326] flex items-center justify-between text-xs overflow-x-auto gap-2">
        <div className="flex items-center gap-1.5 shrink-0">
          <span className="text-[10px] uppercase font-semibold text-[#555559]">
            Model:
          </span>
          <select
            value={selectedModel}
            onChange={(e) => setSelectedModel(e.target.value as any)}
            className="bg-[#212124] text-[#F0F0F0] text-xs px-2.5 py-1 rounded-lg border border-[#232326] outline-none"
          >
            <option value="gemini-3.8-flash">gemini-3.8-flash (General)</option>
            <option value="gemini-4-argon">
              gemini-4-argon (Complex reasoning)
            </option>
            <option value="gemini-3.1-flash-lite">
              gemini-3.1-flash-lite (Fast)
            </option>
          </select>
        </div>

        {/* Grounding Mode Pills */}
        <div className="flex items-center gap-1 shrink-0">
          <button
            onClick={() =>
              setActiveTool(activeTool === 'search' ? 'none' : 'search')
            }
            className={`flex items-center gap-1 px-2.5 py-1 rounded-lg border transition-colors ${
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
            className={`flex items-center gap-1 px-2.5 py-1 rounded-lg border transition-colors ${
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

      {/* Messages Scroll View */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {messages.map((msg) => (
          <div
            key={msg.id}
            className={`flex flex-col ${
              msg.sender === 'user' ? 'items-end' : 'items-start'
            }`}
          >
            <div
              className={`max-w-[85%] rounded-2xl p-4 text-xs sm:text-sm leading-relaxed ${
                msg.sender === 'user'
                  ? 'bg-[#2FB083] text-[#0C0C0D] font-medium rounded-tr-sm'
                  : 'bg-[#1C1C1F] text-[#F0F0F0] border border-[#232326] rounded-tl-sm shadow-sm'
              }`}
            >
              <p className="whitespace-pre-wrap">{msg.text}</p>

              {/* Search Grounding Citation Sources */}
              {msg.sources && msg.sources.length > 0 && (
                <div className="mt-3 pt-2.5 border-t border-[#232326] space-y-1.5">
                  <span className="text-[10px] font-semibold tracking-wider text-[#2FB083] uppercase flex items-center gap-1">
                    <Globe className="w-3 h-3" />
                    Search Sources:
                  </span>
                  <div className="flex flex-wrap gap-1.5">
                    {msg.sources.map((src, sIdx) => (
                      <a
                        key={sIdx}
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

              {/* Maps Grounding Place Cards */}
              {msg.places && msg.places.length > 0 && (
                <div className="mt-3 pt-2.5 border-t border-[#232326] space-y-1.5">
                  <span className="text-[10px] font-semibold tracking-wider text-[#7AA7A0] uppercase flex items-center gap-1">
                    <MapPin className="w-3 h-3" />
                    Recommended Places:
                  </span>
                  <div className="space-y-1.5">
                    {msg.places.map((place, pIdx) => (
                      <a
                        key={pIdx}
                        href={place.uri}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="flex items-center justify-between p-2 rounded-lg bg-[#212124] hover:bg-[#28282C] text-xs text-[#F0F0F0] border border-[#232326] transition-colors"
                      >
                        <span className="font-medium truncate">
                          {place.title}
                        </span>
                        <div className="flex items-center gap-1 text-[11px] text-[#7AA7A0] shrink-0 ml-2">
                          <span>View on Maps</span>
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

            {/* Interactive Proposal Card */}
            {msg.proposal && (
              <div className="mt-2 max-w-[85%] bg-[#161618] border border-[#2FB083]/30 rounded-xl p-3 shadow-md">
                <div className="flex items-center gap-1.5 text-[11px] font-semibold text-[#2FB083] uppercase mb-1">
                  <Sparkles className="w-3.5 h-3.5" />
                  <span>Suggested Action</span>
                </div>
                <p className="text-xs text-[#F0F0F0] mb-2.5">
                  {msg.proposal.confirmationPrompt}
                </p>

                {appliedProposals[msg.id] ? (
                  <div className="flex items-center gap-1.5 text-xs text-[#2FB083] font-medium pt-1">
                    <Check className="w-4 h-4" />
                    <span>Applied to your plan</span>
                  </div>
                ) : (
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() =>
                        handleConfirmProposal(msg.id, msg.proposal!)
                      }
                      className="px-3 py-1.5 bg-[#2FB083] text-[#0C0C0D] rounded-lg text-xs font-semibold hover:bg-[#2FB083]/90 transition-colors"
                    >
                      Confirm
                    </button>
                    <button
                      onClick={() =>
                        setAppliedProposals((prev) => ({
                          ...prev,
                          [msg.id]: true,
                        }))
                      }
                      className="px-2.5 py-1.5 text-xs text-[#8A8A8E] hover:text-[#F0F0F0]"
                    >
                      Not now
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
            <span>Lexi is thinking…</span>
          </div>
        )}

        <div ref={messagesEndRef} />
      </div>

      {/* Suggested Quick Action Chips */}
      <div className="px-4 py-2 border-t border-[#232326] bg-[#161618]/60 flex items-center gap-2 overflow-x-auto no-scrollbar">
        <button
          onClick={() => handleSend("I'm feeling stuck and can't start.")}
          className="whitespace-nowrap px-3 py-1 rounded-full bg-[#1C1C1F] hover:bg-[#212124] text-[11px] text-[#8A8A8E] border border-[#232326] transition-colors"
        >
          Break inertia
        </button>
        <button
          onClick={() => {
            setActiveTool('search');
            handleSend(
              'What are evidence-based tips to overcome ADHD task paralysis?',
            );
          }}
          className="whitespace-nowrap px-3 py-1 rounded-full bg-[#1C1C1F] hover:bg-[#212124] text-[11px] text-[#8A8A8E] border border-[#232326] transition-colors"
        >
          Search ADHD tips
        </button>
        <button
          onClick={() => {
            setActiveTool('maps');
            handleSend('Find quiet study cafes or libraries nearby.');
          }}
          className="whitespace-nowrap px-3 py-1 rounded-full bg-[#1C1C1F] hover:bg-[#212124] text-[11px] text-[#8A8A8E] border border-[#232326] transition-colors"
        >
          Quiet spaces nearby
        </button>
      </div>

      {/* Audio Transcription Status Indicator */}
      {(isRecording || isTranscribing) && (
        <div className="px-4 py-1.5 bg-[#2FB083]/15 text-xs text-[#2FB083] flex items-center justify-between border-t border-[#2FB083]/20">
          <span className="flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-red-500 animate-ping" />
            {isRecording
              ? 'Recording speech… tap microphone to transcribe with gemini-3.5-transcribe'
              : 'Transcribing speech…'}
          </span>
        </div>
      )}

      {recordingError && (
        <p role="alert" className="px-4 py-2 text-xs text-red-300">
          {recordingError}
        </p>
      )}
      {/* Input Field */}
      <div className="p-3 bg-[#161618] border-t border-[#232326] flex items-center gap-2">
        {/* Audio Mic Button (gemini-3.5-transcribe) */}
        <button
          onClick={handleMicToggle}
          className={`p-2.5 rounded-xl border transition-colors ${
            isRecording
              ? 'bg-red-600 text-white border-red-500 animate-pulse'
              : 'bg-[#1C1C1F] text-[#8A8A8E] hover:text-[#2FB083] border-[#232326]'
          }`}
          title={
            isRecording ? 'Stop & Transcribe' : 'Transcribe speech with Gemini'
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
              ? 'Search Google with Lexi…'
              : activeTool === 'maps'
                ? 'Search Google Maps for places…'
                : 'Message Lexi…'
          }
          className="flex-1 bg-[#1C1C1F] text-[#F0F0F0] text-sm px-4 py-2.5 rounded-xl border border-[#232326] focus:border-[#2FB083] outline-none"
        />

        <button
          onClick={() => handleSend()}
          disabled={!input.trim() || isGenerating}
          className="p-2.5 bg-[#2FB083] text-[#0C0C0D] rounded-xl disabled:opacity-30 hover:bg-[#2FB083]/90 transition-colors"
        >
          <Send className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};
