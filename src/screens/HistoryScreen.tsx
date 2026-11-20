import React from 'react';
import { Clock, CheckCircle2, Calendar, History, ArrowUpRight } from 'lucide-react';
import { Task } from '../types';

interface HistoryScreenProps {
  tasks: Task[];
  refresh: () => void;
}

function formatElapsed(totalSeconds: number): string {
  if (!totalSeconds || totalSeconds < 60) {
    return `${Math.max(1, totalSeconds || 0)}s`;
  }
  const mins = Math.floor(totalSeconds / 60);
  const secs = totalSeconds % 60;
  if (mins < 60) {
    return secs > 0 ? `${mins}m ${secs}s` : `${mins}m`;
  }
  const hours = Math.floor(mins / 60);
  const remainingMins = mins % 60;
  return remainingMins > 0 ? `${hours}h ${remainingMins}m` : `${hours}h`;
}

function formatFinishedDate(isoString?: string): string {
  if (!isoString) return 'Completed';
  const d = new Date(isoString);
  if (isNaN(d.getTime())) return 'Completed';

  const today = new Date();
  const isToday =
    d.getDate() === today.getDate() &&
    d.getMonth() === today.getMonth() &&
    d.getFullYear() === today.getFullYear();

  const timeStr = d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  if (isToday) {
    return `Today at ${timeStr}`;
  }

  const dateStr = d.toLocaleDateString([], { month: 'short', day: 'numeric' });
  return `${dateStr} at ${timeStr}`;
}

export const HistoryScreen: React.FC<HistoryScreenProps> = ({ tasks }) => {
  // Filter for finished tasks only, sorted newest finished first
  const finishedTasks = tasks
    .filter((t) => t.status === 'finished')
    .sort((a, b) => {
      const timeA = a.completedAt ? new Date(a.completedAt).getTime() : 0;
      const timeB = b.completedAt ? new Date(b.completedAt).getTime() : 0;
      return timeB - timeA;
    });

  return (
    <div className="p-4 sm:p-6 pb-28 max-w-2xl mx-auto w-full">
      {/* Header */}
      <div className="mb-6">
        <h2 className="text-xl sm:text-2xl font-semibold text-[#F0F0F0] tracking-tight">
          History & Reflection
        </h2>
        <p className="text-xs sm:text-sm text-[#8A8A8E] mt-0.5">
          Quiet record of what got done, when, and active time spent
        </p>
      </div>

      {finishedTasks.length === 0 ? (
        <div className="p-8 text-center bg-[#161618] rounded-3xl border border-[#232326]">
          <History className="w-8 h-8 text-[#555559] mx-auto mb-2.5 stroke-[1.5]" />
          <p className="text-sm text-[#8A8A8E]">
            No completed tasks yet. Finish a task on the Now card and it will rest here quietly.
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {finishedTasks.map((t) => {
            const completedSteps = t.microSteps?.filter((s) => s.completed) || [];
            const elapsedDisplay = formatElapsed(t.accumulatedActiveSeconds || 0);
            const finishedDateDisplay = formatFinishedDate(t.completedAt);

            return (
              <div
                key={t.id}
                className="p-4 rounded-3xl bg-[#161618] border border-[#232326] transition-all"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1 flex-wrap">
                      <span className="text-xs text-[#2FB083] font-medium flex items-center gap-1">
                        <CheckCircle2 className="w-3.5 h-3.5 text-[#2FB083]" />
                        <span>Finished</span>
                      </span>
                      <span className="text-[11px] text-[#555559]">·</span>
                      <span className="text-xs text-[#8A8A8E] flex items-center gap-1">
                        <Calendar className="w-3 h-3 text-[#8A8A8E]" />
                        <span>{finishedDateDisplay}</span>
                      </span>
                      <span className="text-[11px] text-[#555559]">·</span>
                      <span className="text-xs text-[#D9A441] font-medium flex items-center gap-1">
                        <Clock className="w-3 h-3 text-[#D9A441]" />
                        <span>{elapsedDisplay} active</span>
                      </span>
                    </div>

                    <h3 className="text-sm sm:text-base font-semibold text-[#F0F0F0] mt-1 break-words">
                      {t.title}
                    </h3>

                    {t.originalWording && t.originalWording !== t.title && (
                      <p className="text-xs text-[#8A8A8E] italic mt-0.5 break-words">
                        "{t.originalWording}"
                      </p>
                    )}

                    {/* Completed Micro-steps */}
                    {completedSteps.length > 0 && (
                      <div className="mt-3 pt-2.5 border-t border-[#232326]/70 space-y-1">
                        <span className="text-[11px] text-[#8A8A8E] block mb-1">
                          Completed steps:
                        </span>
                        {completedSteps.map((step) => (
                          <div
                            key={step.id}
                            className="flex items-center gap-1.5 text-xs text-[#8A8A8E]"
                          >
                            <CheckCircle2 className="w-3 h-3 text-[#2FB083] shrink-0" />
                            <span>{step.title}</span>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};
