import React, { useState } from 'react';
import { X, Trash2, Calendar, Clock, BatteryLow, BatteryMedium, Battery } from 'lucide-react';
import { EnergyLevel, Task } from '../types';
import { taskStorage } from '../lib/storage';

interface TaskEditSheetProps {
  task: Task | null;
  isOpen: boolean;
  onClose: () => void;
  onUpdated?: () => void;
}

export const TaskEditSheet: React.FC<TaskEditSheetProps> = ({
  task,
  isOpen,
  onClose,
  onUpdated,
}) => {
  if (!isOpen || !task) return null;

  return (
    <TaskEditForm
      key={task.id}
      task={task}
      onClose={onClose}
      onUpdated={onUpdated}
    />
  );
};

interface FormProps {
  task: Task;
  onClose: () => void;
  onUpdated?: () => void;
}

const TaskEditForm: React.FC<FormProps> = ({ task, onClose, onUpdated }) => {
  const [title, setTitle] = useState(task.title);
  const [notes, setNotes] = useState(task.notes || '');
  const [energy, setEnergy] = useState<EnergyLevel>(task.energy);
  const [hasTime, setHasTime] = useState(!!task.dueDate);
  const [timeStr, setTimeStr] = useState(() => {
    if (task.dueDate) {
      const d = new Date(task.dueDate);
      const h = String(d.getHours()).padStart(2, '0');
      const m = String(d.getMinutes()).padStart(2, '0');
      return `${h}:${m}`;
    }
    return '09:00';
  });

  const handleSave = (e: React.FormEvent) => {
    e.preventDefault();
    const cleanTitle = title.trim();
    if (!cleanTitle) return;

    let dueDate = task.dueDate;
    if (hasTime) {
      const base = task.dueDate ? new Date(task.dueDate) : new Date();
      const [h, m] = timeStr.split(':').map(Number);
      base.setHours(h || 9, m || 0, 0, 0);
      dueDate = base.toISOString();
    } else {
      dueDate = undefined;
    }

    const updated: Task = {
      ...task,
      title: cleanTitle,
      notes: notes.trim() || undefined,
      energy,
      dueDate,
      isQuickWin: energy === 'low',
    };

    taskStorage.save(updated);
    if (onUpdated) onUpdated();
    onClose();
  };

  const handleDelete = () => {
    if (window.confirm('Delete this task?')) {
      taskStorage.delete(task.id);
      if (onUpdated) onUpdated();
      onClose();
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200">
      <div
        className="w-full max-w-lg bg-[#161618] border-t sm:border border-[#232326] rounded-t-2xl sm:rounded-2xl p-5 shadow-2xl animate-in slide-in-from-bottom duration-250 max-h-[90vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between pb-3 border-b border-[#232326]">
          <h3 className="text-base font-medium text-[#F0F0F0]">Edit Timeline Item</h3>
          <button
            onClick={onClose}
            className="text-[#8A8A8E] hover:text-[#F0F0F0] p-1 rounded-lg"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSave} className="mt-4 space-y-4">
          <div>
            <label className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block mb-1">
              Task Name
            </label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-sm px-3.5 py-2.5 rounded-xl border border-[#232326] focus:border-[#2FB083] outline-none"
            />
          </div>

          <div>
            <label className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block mb-1">
              Notes (Optional)
            </label>
            <textarea
              rows={3}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Context or helpful next step..."
              className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-sm px-3.5 py-2.5 rounded-xl border border-[#232326] focus:border-[#2FB083] outline-none resize-none"
            />
          </div>

          {/* Time settings */}
          <div className="bg-[#1C1C1F] rounded-xl p-3 border border-[#232326] space-y-2">
            <div className="flex items-center justify-between text-xs">
              <span className="text-[#8A8A8E] flex items-center gap-1.5">
                <Calendar className="w-3.5 h-3.5 text-[#2FB083]" />
                {hasTime ? 'Specific scheduled time' : 'Flexible (No set time)'}
              </span>
              <button
                type="button"
                onClick={() => setHasTime(!hasTime)}
                className="text-xs text-[#2FB083] hover:underline"
              >
                {hasTime ? 'Make flexible' : 'Set specific time'}
              </button>
            </div>

            {hasTime && (
              <div className="flex items-center gap-2 pt-2 border-t border-[#232326]">
                <Clock className="w-4 h-4 text-[#8A8A8E]" />
                <label className="text-xs text-[#8A8A8E]">Time:</label>
                <input
                  type="time"
                  value={timeStr}
                  onChange={(e) => setTimeStr(e.target.value)}
                  className="bg-[#212124] text-[#F0F0F0] text-sm px-2.5 py-1 rounded-lg border border-[#232326] outline-none"
                />
              </div>
            )}
          </div>

          {/* Energy Level */}
          <div>
            <label className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block mb-2">
              Energy to Start
            </label>
            <div className="grid grid-cols-3 gap-2">
              <button
                type="button"
                onClick={() => setEnergy('low')}
                className={`flex items-center justify-center gap-2 p-2.5 rounded-xl border text-xs font-medium transition-all ${
                  energy === 'low'
                    ? 'bg-[#2FB083]/15 text-[#2FB083] border-[#2FB083]/40'
                    : 'bg-[#1C1C1F] text-[#8A8A8E] border-[#232326]'
                }`}
              >
                <BatteryLow className="w-4 h-4" />
                <span>Low</span>
              </button>

              <button
                type="button"
                onClick={() => setEnergy('medium')}
                className={`flex items-center justify-center gap-2 p-2.5 rounded-xl border text-xs font-medium transition-all ${
                  energy === 'medium'
                    ? 'bg-[#2FB083]/15 text-[#2FB083] border-[#2FB083]/40'
                    : 'bg-[#1C1C1F] text-[#8A8A8E] border-[#232326]'
                }`}
              >
                <BatteryMedium className="w-4 h-4" />
                <span>Medium</span>
              </button>

              <button
                type="button"
                onClick={() => setEnergy('high')}
                className={`flex items-center justify-center gap-2 p-2.5 rounded-xl border text-xs font-medium transition-all ${
                  energy === 'high'
                    ? 'bg-[#2FB083]/15 text-[#2FB083] border-[#2FB083]/40'
                    : 'bg-[#1C1C1F] text-[#8A8A8E] border-[#232326]'
                }`}
              >
                <Battery className="w-4 h-4" />
                <span>High</span>
              </button>
            </div>
          </div>

          <div className="pt-3 flex items-center justify-between border-t border-[#232326]">
            <button
              type="button"
              onClick={handleDelete}
              className="text-[#D9A441] hover:text-[#D9A441]/80 text-xs flex items-center gap-1.5 p-2 rounded-lg"
            >
              <Trash2 className="w-4 h-4" />
              <span>Delete</span>
            </button>

            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={onClose}
                className="px-4 py-2 text-xs text-[#8A8A8E] hover:text-[#F0F0F0]"
              >
                Cancel
              </button>
              <button
                type="submit"
                className="px-5 py-2.5 bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] rounded-xl text-xs font-semibold"
              >
                Save Changes
              </button>
            </div>
          </div>
        </form>
      </div>
    </div>
  );
};
