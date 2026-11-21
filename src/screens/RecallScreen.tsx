import React, { useState } from 'react';
import { Search, Sparkles, ArrowRight, Edit3, Trash2, CheckCircle2, Inbox, Clock } from 'lucide-react';
import { Task } from '../types';
import { taskStorage } from '../lib/storage';
import { ClarifyModal } from '../components/ClarifyModal';

interface RecallScreenProps {
  tasks: Task[];
  onPickAndGoToNow: (task: Task) => void;
  refresh: () => void;
}

export const RecallScreen: React.FC<RecallScreenProps> = ({
  tasks,
  onPickAndGoToNow,
  refresh,
}) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [filterTab, setFilterTab] = useState<'all' | 'captured' | 'clarified'>('all');
  const [clarifyingTask, setClarifyingTask] = useState<Task | null>(null);

  // Filter out finished tasks (finished tasks belong quietly in History)
  // Sort newest first per Slice 1 spec: "lists captures and tasks in the order they arrived, newest first"
  const activeAndInboxTasks = tasks
    .filter((t) => t.status !== 'finished')
    .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

  const filteredTasks = activeAndInboxTasks.filter((t) => {
    // Word search matching title or original wording
    const q = searchQuery.toLowerCase().trim();
    const matchSearch =
      !q ||
      t.title.toLowerCase().includes(q) ||
      (t.originalWording && t.originalWording.toLowerCase().includes(q)) ||
      (t.notes && t.notes.toLowerCase().includes(q));

    if (!matchSearch) return false;

    if (filterTab === 'captured') return t.status === 'captured';
    if (filterTab === 'clarified') return t.status === 'clarified';
    return true;
  });

  const handlePickNext = (task: Task) => {
    const picked = taskStorage.pickTask(task.id);
    refresh();
    if (picked) {
      onPickAndGoToNow(picked);
    }
  };

  const handleDelete = (id: string) => {
    taskStorage.delete(id);
    refresh();
  };

  return (
    <div className="p-4 sm:p-6 pb-28 max-w-2xl mx-auto w-full">
      {/* Header */}
      <div className="mb-4">
        <h2 className="text-xl sm:text-2xl font-semibold text-[#F0F0F0] tracking-tight">
          Recall & Inbox
        </h2>
        <p className="text-xs sm:text-sm text-[#8A8A8E] mt-0.5">
          Everything captured and said, in order of arrival
        </p>
      </div>

      {/* Instant Search Bar */}
      <div className="relative mb-3.5">
        <Search className="w-4 h-4 absolute left-3.5 top-3.5 text-[#555559]" />
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="Search by words or phrases..."
          className="w-full bg-[#161618] text-[#F0F0F0] placeholder-[#555559] rounded-2xl pl-10 pr-4 py-2.5 text-sm border border-[#232326] focus:border-[#2FB083] outline-none transition-colors"
        />
        {searchQuery && (
          <button
            onClick={() => setSearchQuery('')}
            className="absolute right-3.5 top-3 text-xs text-[#8A8A8E] hover:text-[#F0F0F0]"
          >
            Clear
          </button>
        )}
      </div>

      {/* Filter Tabs */}
      <div className="flex items-center gap-1.5 mb-4">
        <button
          onClick={() => setFilterTab('all')}
          className={`px-3 py-1.5 rounded-xl text-xs font-medium border transition-colors ${
            filterTab === 'all'
              ? 'bg-[#2FB083]/15 text-[#2FB083] border-[#2FB083]/30'
              : 'bg-[#161618] text-[#8A8A8E] border-[#232326]'
          }`}
        >
          All ({activeAndInboxTasks.length})
        </button>
        <button
          onClick={() => setFilterTab('captured')}
          className={`px-3 py-1.5 rounded-xl text-xs font-medium border transition-colors ${
            filterTab === 'captured'
              ? 'bg-[#2FB083]/15 text-[#2FB083] border-[#2FB083]/30'
              : 'bg-[#161618] text-[#8A8A8E] border-[#232326]'
          }`}
        >
          Inbox ({activeAndInboxTasks.filter((t) => t.status === 'captured').length})
        </button>
        <button
          onClick={() => setFilterTab('clarified')}
          className={`px-3 py-1.5 rounded-xl text-xs font-medium border transition-colors ${
            filterTab === 'clarified'
              ? 'bg-[#2FB083]/15 text-[#2FB083] border-[#2FB083]/30'
              : 'bg-[#161618] text-[#8A8A8E] border-[#232326]'
          }`}
        >
          Clarified ({activeAndInboxTasks.filter((t) => t.status === 'clarified').length})
        </button>
      </div>

      {/* Tasks List */}
      {filteredTasks.length === 0 ? (
        <div className="p-8 text-center bg-[#161618] rounded-3xl border border-[#232326] mt-4">
          <Inbox className="w-8 h-8 text-[#555559] mx-auto mb-2.5 stroke-[1.5]" />
          <p className="text-sm text-[#8A8A8E]">
            {searchQuery
              ? `No items match "${searchQuery}".`
              : filterTab === 'captured'
              ? 'Inbox is clear. Every capture has been clarified or picked.'
              : 'No items yet. Tap + to capture a thought.'}
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {filteredTasks.map((t) => {
            const isPicked = t.status === 'picked';
            const isActive = t.status === 'active' || t.status === 'resumed';
            const isPaused = t.status === 'paused';

            return (
              <div
                key={t.id}
                className={`p-4 rounded-3xl border transition-all ${
                  isPicked || isActive || isPaused
                    ? 'bg-[#1C1C1F] border-[#2FB083]/40 ring-1 ring-[#2FB083]/30'
                    : 'bg-[#161618] border-[#232326] hover:border-[#2C2C30]'
                }`}
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="flex-1 min-w-0">
                    {/* Status Badge */}
                    <div className="flex items-center gap-2 mb-1.5 flex-wrap">
                      <span
                        className={`text-[10px] font-semibold uppercase tracking-wider px-2 py-0.5 rounded-md ${
                          t.status === 'captured'
                            ? 'bg-[#2A2A2E] text-[#8A8A8E]'
                            : t.status === 'clarified'
                            ? 'bg-[#D9A441]/15 text-[#D9A441]'
                            : t.status === 'picked'
                            ? 'bg-[#2FB083]/20 text-[#2FB083]'
                            : t.status === 'paused'
                            ? 'bg-[#D9A441]/20 text-[#D9A441]'
                            : 'bg-[#2FB083] text-[#0C0C0D]'
                        }`}
                      >
                        {t.status}
                      </span>
                      {t.estimatedMinutes && (
                        <span className="text-[11px] text-[#8A8A8E] flex items-center gap-1">
                          <Clock className="w-3 h-3 text-[#D9A441]" />
                          <span>~{t.estimatedMinutes}m</span>
                        </span>
                      )}
                      {t.microSteps && t.microSteps.length > 0 && (
                        <span className="text-[11px] text-[#8A8A8E]">
                          {t.microSteps.filter((s) => s.completed).length}/{t.microSteps.length} steps
                        </span>
                      )}
                    </div>

                    {/* Title */}
                    <h3 className="text-sm sm:text-base font-semibold text-[#F0F0F0] leading-snug break-words">
                      {t.title}
                    </h3>

                    {/* Verbatim quote if title was edited during clarify */}
                    {t.originalWording && t.originalWording !== t.title && (
                      <p className="text-xs text-[#8A8A8E] italic mt-1 break-words">
                        "{t.originalWording}"
                      </p>
                    )}
                  </div>

                  {/* Delete action */}
                  <button
                    onClick={() => handleDelete(t.id)}
                    className="text-[#555559] hover:text-red-400 p-1.5 rounded-lg hover:bg-[#232326] transition-colors"
                    title="Delete item"
                    aria-label="Delete"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>

                {/* 1-Tap Actions: Pick Next, Clarify, or Leave in Inbox */}
                <div className="mt-3.5 pt-3 border-t border-[#232326] flex items-center justify-between gap-2 flex-wrap">
                  <div className="flex items-center gap-1.5">
                    <button
                      onClick={() => setClarifyingTask(t)}
                      className="px-3 py-1.5 rounded-xl bg-[#212124] hover:bg-[#28282C] text-xs text-[#F0F0F0] font-medium flex items-center gap-1.5 transition-colors border border-[#2A2A2E]"
                    >
                      <Edit3 className="w-3.5 h-3.5 text-[#D9A441]" />
                      <span>Clarify</span>
                    </button>
                  </div>

                  <div className="flex items-center gap-2">
                    {isPicked || isActive || isPaused ? (
                      <button
                        onClick={() => onPickAndGoToNow(t)}
                        className="px-4 py-1.5 rounded-xl bg-[#2FB083]/15 hover:bg-[#2FB083]/25 text-[#2FB083] text-xs font-semibold flex items-center gap-1 transition-colors border border-[#2FB083]/40"
                      >
                        <span>View on Now Card</span>
                        <ArrowRight className="w-3.5 h-3.5" />
                      </button>
                    ) : (
                      <button
                        onClick={() => handlePickNext(t)}
                        className="px-4 py-1.5 rounded-xl bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] text-xs font-semibold flex items-center gap-1 transition-all shadow-sm shadow-[#2FB083]/20 active:scale-95"
                      >
                        <span>Pick Next</span>
                        <ArrowRight className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Clarify Modal */}
      {clarifyingTask && (
        <ClarifyModal
          task={clarifyingTask}
          isOpen={Boolean(clarifyingTask)}
          onClose={() => setClarifyingTask(null)}
          onClarified={() => {
            refresh();
            setClarifyingTask(null);
          }}
          onClarifyAndPick={(task) => {
            refresh();
            setClarifyingTask(null);
            onPickAndGoToNow(task);
          }}
        />
      )}
    </div>
  );
};
