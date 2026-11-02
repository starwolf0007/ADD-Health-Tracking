// Domain types mirroring NeuroFlow's pure Dart domain models

export type EnergyLevel = 'low' | 'medium' | 'high';

export type TaskStatus = 'pending' | 'inProgress' | 'completed' | 'skipped' | 'paused' | 'blocked';

export interface ReentryNote {
  lastCompletedStep?: string;
  nextAction?: string;
  returnAt?: string; // ISO date
  updatedAt: string;
}

export interface Task {
  id: string;
  title: string;
  notes?: string;
  energy: EnergyLevel;
  status: TaskStatus;
  createdAt: string; // ISO date
  dueDate?: string; // ISO date
  completedAt?: string;
  activeStartedAt?: string;
  estimatedMinutes?: number;
  reentryNote?: ReentryNote;
  isQuickWin: boolean;
  googleTaskId?: string;
}

export type RoutineAnchor = 'morning' | 'midday' | 'evening' | 'custom';

export interface RoutineStep {
  id: string;
  routineId: string;
  position: number;
  title: string;
  notes?: string;
  durationMinutes?: number;
  isComplete: boolean;
}

export interface Routine {
  id: string;
  name: string;
  anchor: RoutineAnchor;
  scheduleHour?: number;
  scheduleMinute?: number;
  isActive: boolean;
  activeDays?: string; // e.g. "12345" for Mon-Fri, or null for everyday
  steps: RoutineStep[];
  createdAt: string;
}

export type HabitFrequency = 'daily' | 'weekdays' | 'weekends';

export interface HabitCheckIn {
  id: string;
  habitId: string;
  date: string; // YYYY-MM-DD
  completed: boolean;
  createdAt: string;
}

export interface Habit {
  id: string;
  name: string;
  icon?: string;
  notes?: string;
  frequency: HabitFrequency;
  isActive: boolean;
  createdAt: string;
}

export type MoodLevel = 'veryLow' | 'low' | 'neutral' | 'good' | 'great';

export interface MoodLog {
  id: string;
  level: MoodLevel;
  note?: string;
  loggedAt: string; // ISO date
}

export interface Note {
  id: string;
  body: string;
  pinned: boolean;
  linkedTaskId?: string;
  createdAt: string;
  updatedAt: string;
}

export type DayMode = 'normal' | 'quickWins';

export type TimelineItemType = 'calendarEvent' | 'fixedAnchor' | 'flexibleBlock' | 'task' | 'openSpace';

export type TimelinePhase = 'past' | 'current' | 'upcoming';

export interface TimelineItem {
  id: string;
  type: TimelineItemType;
  title: string;
  subtitle?: string;
  start?: string; // ISO date
  end?: string; // ISO date
  task?: Task;
  isCompleted?: boolean;
  isPaused?: boolean;
}

export interface Plan {
  mode: DayMode;
  primaryTask?: Task;
  quickWins: Task[];
  reason: string;
}

export interface Achievement {
  id: string;
  title: string;
  message: string;
  type: 'reentry' | 'quickwin' | 'routine' | 'backup';
  timestamp: number;
}


export interface HevySet {
  index: number;
  type: string;
  weightKg?: number;
  reps?: number;
  distanceMeters?: number;
  durationSeconds?: number;
  rpe?: number;
}

export interface HevyExercise {
  index: number;
  title: string;
  notes?: string;
  sets: HevySet[];
}

export interface HevyWorkout {
  id: string;
  title: string;
  description?: string;
  startTime: string;
  endTime: string;
  exercises: HevyExercise[];
}

export interface LexiProposal {
  type: 'start_task' | 'pause_task' | 'create_reentry_note';
  payload: {
    taskId: string;
    nextAction?: string;
  };
  requiresConfirmation: boolean;
  confirmationPrompt: string;
}

export interface LexiResponse {
  dialogue: string;
  contextUsedSummary: string[];
  proposal?: LexiProposal | null;
  memoryCandidate?: string | null;
}
