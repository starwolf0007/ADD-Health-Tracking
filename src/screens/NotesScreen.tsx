import React, { useState } from 'react';
import {
  StickyNote,
  Plus,
  Pin,
  Trash2,
  ArrowUpRight,
  X,
  Clock,
} from 'lucide-react';
import { Note, Task } from '../types';
import { noteStorage, taskStorage } from '../lib/storage';

interface NotesScreenProps {
  notes: Note[];
  refresh: () => void;
}

export const NotesScreen: React.FC<NotesScreenProps> = ({ notes, refresh }) => {
  const [editingNote, setEditingNote] = useState<Note | null>(null);
  const [isCreating, setIsCreating] = useState(false);
  const [newBody, setNewBody] = useState('');
  const [deleteConfirmId, setDeleteConfirmId] = useState<string | null>(null);
  const [promoteNotice, setPromoteNotice] = useState<string | null>(null);

  const sortedNotes = [...notes].sort((a, b) => {
    if (a.pinned && !b.pinned) return -1;
    if (!a.pinned && b.pinned) return 1;
    return new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime();
  });

  const handleCreate = (e: React.FormEvent) => {
    e.preventDefault();
    const clean = newBody.trim();
    if (!clean) return;

    const newNote: Note = {
      id: `note-${Date.now()}`,
      body: clean,
      pinned: false,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    noteStorage.save(newNote);
    setNewBody('');
    setIsCreating(false);
    refresh();
  };

  const handleUpdate = (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingNote) return;
    const clean = editingNote.body.trim();
    if (!clean) return;

    noteStorage.save({
      ...editingNote,
      body: clean,
      updatedAt: new Date().toISOString(),
    });
    setEditingNote(null);
    refresh();
  };

  const handleTogglePin = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    noteStorage.togglePin(id);
    refresh();
  };

  const handleDelete = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (deleteConfirmId !== id) {
      setDeleteConfirmId(id);
      return;
    }
    noteStorage.delete(id);
    setDeleteConfirmId(null);
    refresh();
  };

  const handlePromoteToTask = (note: Note, e: React.MouseEvent) => {
    e.stopPropagation();
    const firstLineEnd = note.body.indexOf('\n');
    const title = (firstLineEnd === -1 ? note.body : note.body.substring(0, firstLineEnd)).trim();
    const rest = firstLineEnd === -1 ? undefined : note.body.substring(firstLineEnd + 1).trim();

    const newTask: Task = {
      id: `task-${Date.now()}`,
      title,
      notes: rest || undefined,
      energy: 'medium',
      status: 'pending',
      createdAt: new Date().toISOString(),
      isQuickWin: false,
    };

    taskStorage.save(newTask);
    setPromoteNotice(`Promoted to Today: "${title}"`);
    setTimeout(() => setPromoteNotice(null), 4000);
    refresh();
  };

  const formatRelativeTime = (isoDate: string) => {
    const diffMs = Date.now() - new Date(isoDate).getTime();
    const diffSecs = Math.floor(diffMs / 1000);
    const diffMins = Math.floor(diffSecs / 60);
    const diffHours = Math.floor(diffMins / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;
    return new Date(isoDate).toLocaleDateString();
  };

  return (
    <div className="pb-28 max-w-2xl mx-auto px-4 pt-3 space-y-4">
      <div className="flex items-center justify-between pb-2 border-b border-[#232326]">
        <div>
          <h2 className="text-lg font-semibold text-[#F0F0F0]">Notes</h2>
          <p className="text-xs text-[#8A8A8E]">
            Low-friction capture. Promote to task when ready.
          </p>
        </div>
        <button
          onClick={() => setIsCreating(true)}
          className="flex items-center gap-1.5 px-3 py-1.5 bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] rounded-xl text-xs font-semibold shadow-sm transition-colors"
        >
          <Plus className="w-4 h-4" />
          <span>New Note</span>
        </button>
      </div>

      {promoteNotice && (
        <div className="p-3 rounded-xl bg-[#2FB083]/15 border border-[#2FB083]/40 text-xs text-[#2FB083] font-medium">
          {promoteNotice}
        </div>
      )}

      {sortedNotes.length === 0 ? (
        <div className="text-center py-16 px-4 bg-[#161618] border border-dashed border-[#232326] rounded-2xl">
          <StickyNote className="w-10 h-10 text-[#555559] mx-auto mb-3" />
          <h3 className="text-sm font-medium text-[#F0F0F0] mb-1">No notes yet</h3>
          <p className="text-xs text-[#8A8A8E] max-w-xs mx-auto leading-relaxed">
            Capture a thought in one tap. You can promote it to a task later when you have capacity.
          </p>
          <button
            onClick={() => setIsCreating(true)}
            className="mt-4 px-4 py-2 bg-[#212124] hover:bg-[#28282C] text-[#2FB083] text-xs font-medium rounded-xl border border-[#232326]"
          >
            Create first note
          </button>
        </div>
      ) : (
        <div className="space-y-3">
          {sortedNotes.map((note) => (
            <div
              key={note.id}
              onClick={() => setEditingNote(note)}
              className="p-4 bg-[#161618] hover:bg-[#1C1C1F] border border-[#232326] rounded-2xl cursor-pointer transition-all space-y-2.5 shadow-sm group"
            >
              <div className="flex items-start justify-between gap-3">
                <p className="text-sm text-[#F0F0F0] leading-relaxed whitespace-pre-wrap flex-1 break-words">
                  {note.body}
                </p>
                <div className="flex items-center gap-1 shrink-0 text-[#555559]">
                  <button
                    onClick={(e) => handleTogglePin(note.id, e)}
                    className={`p-1.5 rounded-lg hover:text-[#F0F0F0] transition-colors ${
                      note.pinned ? 'text-[#2FB083]' : ''
                    }`}
                    title={note.pinned ? 'Unpin' : 'Pin to top'}
                  >
                    <Pin className="w-4 h-4" />
                  </button>
                  <button
                    onClick={(e) => handlePromoteToTask(note, e)}
                    className="p-1.5 rounded-lg hover:text-[#2FB083] transition-colors"
                    title="Promote to Today Task"
                  >
                    <ArrowUpRight className="w-4 h-4" />
                  </button>
                  <button
                    onClick={(e) => handleDelete(note.id, e)}
                    className={`p-1.5 rounded-lg transition-colors flex items-center gap-1 text-xs ${
                      deleteConfirmId === note.id
                        ? 'bg-[#D9A441] text-[#0C0C0D] font-semibold px-2'
                        : 'hover:text-[#D9A441]'
                    }`}
                    title="Delete note"
                  >
                    <Trash2 className="w-4 h-4" />
                    {deleteConfirmId === note.id && <span>Confirm</span>}
                  </button>
                </div>
              </div>

              <div className="flex items-center gap-2 text-[11px] text-[#555559] pt-1">
                <Clock className="w-3 h-3" />
                <span>{formatRelativeTime(note.updatedAt)}</span>
                {note.pinned && (
                  <span className="text-[#2FB083] font-medium ml-1">· Pinned</span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* New Note Modal Sheet */}
      {isCreating && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200">
          <div
            className="w-full max-w-lg bg-[#161618] border-t sm:border border-[#232326] rounded-t-2xl sm:rounded-2xl p-5 shadow-2xl animate-in slide-in-from-bottom duration-250"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between pb-3 border-b border-[#232326]">
              <h3 className="text-base font-medium text-[#F0F0F0]">New Note</h3>
              <button
                onClick={() => setIsCreating(false)}
                className="text-[#8A8A8E] hover:text-[#F0F0F0] p-1"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <form onSubmit={handleCreate} className="mt-4 space-y-4">
              <textarea
                autoFocus
                rows={5}
                value={newBody}
                onChange={(e) => setNewBody(e.target.value)}
                placeholder="What's on your mind? (Thoughts, temporary items, context...)"
                className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-sm p-3.5 rounded-xl border border-[#232326] focus:border-[#2FB083] outline-none resize-none"
              />

              <div className="flex items-center justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setIsCreating(false)}
                  className="px-4 py-2 text-xs text-[#8A8A8E]"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={!newBody.trim()}
                  className="px-5 py-2.5 bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] rounded-xl text-xs font-semibold disabled:opacity-40"
                >
                  Save Note
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Edit Note Modal Sheet */}
      {editingNote && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200">
          <div
            className="w-full max-w-lg bg-[#161618] border-t sm:border border-[#232326] rounded-t-2xl sm:rounded-2xl p-5 shadow-2xl animate-in slide-in-from-bottom duration-250"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between pb-3 border-b border-[#232326]">
              <h3 className="text-base font-medium text-[#F0F0F0]">Edit Note</h3>
              <button
                onClick={() => setEditingNote(null)}
                className="text-[#8A8A8E] hover:text-[#F0F0F0] p-1"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <form onSubmit={handleUpdate} className="mt-4 space-y-4">
              <textarea
                autoFocus
                rows={6}
                value={editingNote.body}
                onChange={(e) =>
                  setEditingNote({ ...editingNote, body: e.target.value })
                }
                className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-sm p-3.5 rounded-xl border border-[#232326] focus:border-[#2FB083] outline-none resize-none"
              />

              <div className="flex items-center justify-between pt-2">
                <button
                  type="button"
                  onClick={(e) => {
                    handlePromoteToTask(editingNote, e);
                    setEditingNote(null);
                  }}
                  className="text-xs text-[#2FB083] hover:underline flex items-center gap-1"
                >
                  <ArrowUpRight className="w-3.5 h-3.5" />
                  <span>Promote to Task</span>
                </button>

                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => setEditingNote(null)}
                    className="px-4 py-2 text-xs text-[#8A8A8E]"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={!editingNote.body.trim()}
                    className="px-5 py-2.5 bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] rounded-xl text-xs font-semibold"
                  >
                    Save Changes
                  </button>
                </div>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
