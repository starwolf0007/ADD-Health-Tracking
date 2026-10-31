import React, { useState } from 'react';
import {
  ArrowLeft,
  Sparkles,
  Send,
  Check,
  Pause,
  Play,
  RotateCcw,
  CornerDownRight,
  Brain,
} from 'lucide-react';
import { Task, LexiProposal, LexiResponse } from '../types';
import { LexiAvatar } from '../components/LexiAvatar';
import { taskStorage } from '../lib/storage';

interface LexiConversationScreenProps {
  tasks: Task[];
  onBack: () => void;
  refresh: () => void;
}

interface ChatMessage {
  id: string;
  sender: 'lexi' | 'user';
  text: string;
  proposal?: LexiProposal;
}

export const LexiConversationScreen: React.FC<LexiConversationScreenProps> = ({
  tasks,
  onBack,
  refresh,
}) => {
  const pendingTasks = tasks.filter((t) => t.status !== 'completed');
  const recommendedTask = pendingTasks[0] || null;

  const [input, setInput] = useState('');
  const [messages, setMessages] = useState<ChatMessage[]>(() => [
    {
      id: 'msg-init',
      sender: 'lexi',
      text: recommendedTask
        ? `Hey. I took a look at your day. We have "${recommendedTask.title}" ready. How's your energy right now?`
        : 'Hey. Your day is currently clear. Want to capture a thought or set an intention?',
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

  const [appliedProposals, setAppliedProposals] = useState<Record<string, boolean>>({});

  const handleSend = (textToSend?: string) => {
    const text = (textToSend || input).trim();
    if (!text) return;

    const userMsg: ChatMessage = {
      id: `user-${Date.now()}`,
      sender: 'user',
      text,
    };
    setMessages((prev) => [...prev, userMsg]);
    if (!textToSend) setInput('');

    // Generate calm, ADHD-supportive response
    setTimeout(() => {
      let reply = '';
      let newProposal: LexiProposal | undefined = undefined;

      const lower = text.toLowerCase();
      if (lower.includes('stuck') || lower.includes('overwhelm') || lower.includes('hard')) {
        reply =
          "Initiation paralysis is completely normal when tasks feel big. Let's make it absurdly small. Just open the workspace and look at the first line. Nothing else is expected right now.";
        if (recommendedTask) {
          newProposal = {
            type: 'pause_task',
            payload: { taskId: recommendedTask.id },
            requiresConfirmation: true,
            confirmationPrompt: `Pause "${recommendedTask.title}" and take a 5-minute breather?`,
          };
        }
      } else if (lower.includes('rough') || lower.includes('low') || lower.includes('tired')) {
        reply =
          "Thank you for noticing your capacity. Today doesn't need high output. We've shifted into Quick Wins mode — just the easiest low-energy wins, and permission to stop whenever you need.";
      } else if (lower.includes('start') || lower.includes('focus') || lower.includes('ready')) {
        reply = recommendedTask
          ? `Great momentum. Let's start "${recommendedTask.title}". You don't have to finish it, just step into it.`
          : 'Ready whenever you are. Capture a quick task to start.';
        if (recommendedTask) {
          newProposal = {
            type: 'start_task',
            payload: { taskId: recommendedTask.id },
            requiresConfirmation: true,
            confirmationPrompt: `Start "${recommendedTask.title}" now?`,
          };
        }
      } else if (lower.includes('pause') || lower.includes('switch') || lower.includes('break')) {
        reply =
          "Pausing is a valid strategy. Let's preserve your exact return point so you don't lose mental state when you come back.";
        if (recommendedTask) {
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
      } else {
        reply = recommendedTask
          ? `I'm holding "${recommendedTask.title}" as your primary focus. Take it one micro-step at a time.`
          : "I'm right here with you. What feels like the kindest next action for you?";
      }

      setMessages((prev) => [
        ...prev,
        {
          id: `lexi-${Date.now()}`,
          sender: 'lexi',
          text: reply,
          proposal: newProposal,
        },
      ]);
    }, 600);
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

    setAppliedProposals((prev) => ({ ...prev, [msgId]: true }));
    refresh();
  };

  return (
    <div className="fixed inset-0 z-50 bg-[#0C0C0D] flex flex-col max-w-2xl mx-auto shadow-2xl">
      {/* Header */}
      <div className="p-4 flex items-center justify-between border-b border-[#232326] bg-[#161618]">
        <div className="flex items-center gap-3">
          <button
            onClick={onBack}
            className="p-1.5 text-[#8A8A8E] hover:text-[#F0F0F0] rounded-xl"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <LexiAvatar size={36} visualState="thinking" />
          <div>
            <h3 className="text-sm font-medium text-[#F0F0F0]">Lexi</h3>
            <p className="text-[11px] text-[#2FB083]">Executive function companion</p>
          </div>
        </div>
        <span className="text-[10px] font-mono uppercase bg-[#BB86FC]/10 text-[#BB86FC] px-2 py-0.5 rounded-full">
          On-Device Advisor
        </span>
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
                  : 'bg-[#1C1C1F] text-[#F0F0F0] border border-[#232326] rounded-tl-sm'
              }`}
            >
              <p className="whitespace-pre-wrap">{msg.text}</p>
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
                      onClick={() => handleConfirmProposal(msg.id, msg.proposal!)}
                      className="px-3 py-1.5 bg-[#2FB083] text-[#0C0C0D] rounded-lg text-xs font-semibold hover:bg-[#2FB083]/90 transition-colors"
                    >
                      Confirm
                    </button>
                    <button
                      onClick={() =>
                        setAppliedProposals((prev) => ({ ...prev, [msg.id]: true }))
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
      </div>

      {/* Suggested Quick Prompts */}
      <div className="px-4 py-2 border-t border-[#232326] bg-[#161618]/60 flex items-center gap-2 overflow-x-auto no-scrollbar">
        <button
          onClick={() => handleSend("I'm feeling stuck and can't start.")}
          className="whitespace-nowrap px-3 py-1 rounded-full bg-[#1C1C1F] hover:bg-[#212124] text-[11px] text-[#8A8A8E] border border-[#232326] transition-colors"
        >
          I'm feeling stuck
        </button>
        <button
          onClick={() => handleSend("Having a rough afternoon, low energy.")}
          className="whitespace-nowrap px-3 py-1 rounded-full bg-[#1C1C1F] hover:bg-[#212124] text-[11px] text-[#8A8A8E] border border-[#232326] transition-colors"
        >
          Low energy today
        </button>
        <button
          onClick={() => handleSend("I'm ready to focus on my next task.")}
          className="whitespace-nowrap px-3 py-1 rounded-full bg-[#1C1C1F] hover:bg-[#212124] text-[11px] text-[#8A8A8E] border border-[#232326] transition-colors"
        >
          Ready to focus
        </button>
      </div>

      {/* Input Field */}
      <div className="p-3 bg-[#161618] border-t border-[#232326] flex items-center gap-2">
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') handleSend();
          }}
          placeholder="Talk with Lexi..."
          className="flex-1 bg-[#1C1C1F] text-[#F0F0F0] text-sm px-4 py-2.5 rounded-xl border border-[#232326] focus:border-[#2FB083] outline-none"
        />
        <button
          onClick={() => handleSend()}
          disabled={!input.trim()}
          className="p-2.5 bg-[#2FB083] text-[#0C0C0D] rounded-xl disabled:opacity-30 hover:bg-[#2FB083]/90 transition-colors"
        >
          <Send className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};
