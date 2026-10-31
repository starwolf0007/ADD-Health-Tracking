import { Habit, Routine, Task, HevyWorkout } from '../types';

export const APP_COLORS = {
  background: '#0C0C0D',
  accent: '#2FB083',
  accentDim: '#1E7A5A',
  accentWash: 'rgba(47, 176, 131, 0.12)',
  surface: '#161618',
  surfaceRaised: '#1C1C1F',
  surfaceVariant: '#212124',
  surfaceGlass: 'rgba(28, 28, 31, 0.85)',
  divider: '#232326',
  textPrimary: '#F0F0F0',
  textSecondary: '#8A8A8E',
  textMuted: '#555559',
  textFaint: '#3C3C40',
  warning: '#D9A441',
  calendar: '#7AA7A0',
  attention: '#D9A441',
  gold: '#FFD700',
  info: '#2196F3',
  lexi: '#BB86FC',
} as const;

export const SEED_ROUTINES: Routine[] = [
  {
    id: 'routine-morning-start',
    name: 'Morning start',
    anchor: 'morning',
    scheduleHour: 7,
    scheduleMinute: 30,
    isActive: true,
    createdAt: new Date().toISOString(),
    steps: [
      {
        id: 'step-m1',
        routineId: 'routine-morning-start',
        position: 0,
        title: 'Drink a glass of water',
        durationMinutes: 1,
        isComplete: false,
      },
      {
        id: 'step-m2',
        routineId: 'routine-morning-start',
        position: 1,
        title: 'Open curtains or go outside for 2 minutes',
        notes: 'Light exposure resets your circadian clock and lifts morning fog',
        durationMinutes: 2,
        isComplete: false,
      },
      {
        id: 'step-m3',
        routineId: 'routine-morning-start',
        position: 2,
        title: "Check NeuroFlow — what's the one thing today?",
        durationMinutes: 2,
        isComplete: false,
      },
      {
        id: 'step-m4',
        routineId: 'routine-morning-start',
        position: 3,
        title: 'Eat something — even small',
        durationMinutes: 10,
        isComplete: false,
      },
    ],
  },
  {
    id: 'routine-wind-down',
    name: 'Wind down',
    anchor: 'evening',
    scheduleHour: 21,
    scheduleMinute: 0,
    isActive: true,
    createdAt: new Date().toISOString(),
    steps: [
      {
        id: 'step-e1',
        routineId: 'routine-wind-down',
        position: 0,
        title: "Mark today's tasks done or carry forward",
        durationMinutes: 3,
        isComplete: false,
      },
      {
        id: 'step-e2',
        routineId: 'routine-wind-down',
        position: 1,
        title: 'Set one intention for tomorrow',
        notes: 'Just one gentle next step — keep it small',
        durationMinutes: 2,
        isComplete: false,
      },
      {
        id: 'step-e3',
        routineId: 'routine-wind-down',
        position: 2,
        title: 'Phone face-down or on charger outside bedroom',
        durationMinutes: 1,
        isComplete: false,
      },
    ],
  },
];

export const SEED_HABITS: Habit[] = [
  {
    id: 'habit-1',
    name: 'Drink a glass of water',
    frequency: 'daily',
    isActive: true,
    createdAt: new Date(Date.now() - 30 * 86400000).toISOString(),
  },
  {
    id: 'habit-2',
    name: 'Get outside for 5 minutes',
    frequency: 'daily',
    isActive: true,
    createdAt: new Date(Date.now() - 30 * 86400000).toISOString(),
  },
  {
    id: 'habit-3',
    name: 'Phone away 30 min before bed',
    frequency: 'daily',
    isActive: true,
    createdAt: new Date(Date.now() - 30 * 86400000).toISOString(),
  },
];

const now = new Date();
const todayYear = now.getFullYear();
const todayMonth = now.getMonth();
const todayDate = now.getDate();

export const SEED_TASKS: Task[] = [
  {
    id: 'task-1',
    title: 'Review weekly focus and align priorities',
    notes: 'Keep it contained: choose at most 2 critical items',
    energy: 'medium',
    status: 'pending',
    createdAt: new Date().toISOString(),
    dueDate: new Date(todayYear, todayMonth, todayDate, 10, 0).toISOString(),
    estimatedMinutes: 25,
    isQuickWin: false,
  },
  {
    id: 'task-2',
    title: 'Reply to landlord maintenance confirmation',
    notes: 'One line text confirming Thursday 2 PM slot',
    energy: 'low',
    status: 'pending',
    createdAt: new Date().toISOString(),
    dueDate: new Date(todayYear, todayMonth, todayDate, 14, 30).toISOString(),
    estimatedMinutes: 5,
    isQuickWin: true,
  },
  {
    id: 'task-3',
    title: 'Order replacement PETG filament for printer',
    notes: 'Black or grey 1.75mm',
    energy: 'low',
    status: 'pending',
    createdAt: new Date().toISOString(),
    estimatedMinutes: 5,
    isQuickWin: true,
  },
  {
    id: 'task-4',
    title: 'Deep dive: Refactor timeline state projection',
    notes: 'Eliminate duplicate subscriptions; test edge cases',
    energy: 'high',
    status: 'pending',
    createdAt: new Date().toISOString(),
    estimatedMinutes: 45,
    isQuickWin: false,
  },
];

export const SEED_WORKOUTS: HevyWorkout[] = [
  {
    id: 'hevy-w1',
    title: 'Upper Body Power',
    description: 'Chest, shoulders, and triceps focus',
    startTime: new Date(todayYear, todayMonth, todayDate - 1, 17, 30).toISOString(),
    endTime: new Date(todayYear, todayMonth, todayDate - 1, 18, 35).toISOString(),
    exercises: [
      {
        index: 0,
        title: 'Barbell Bench Press',
        sets: [
          { index: 0, type: 'warmup', weightKg: 40, reps: 10 },
          { index: 1, type: 'normal', weightKg: 75, reps: 6 },
          { index: 2, type: 'normal', weightKg: 80, reps: 5 },
          { index: 3, type: 'normal', weightKg: 80, reps: 4 },
        ],
      },
      {
        index: 1,
        title: 'Overhead Dumbbell Press',
        sets: [
          { index: 0, type: 'normal', weightKg: 24, reps: 8 },
          { index: 1, type: 'normal', weightKg: 24, reps: 8 },
        ],
      },
    ],
  },
  {
    id: 'hevy-w2',
    title: 'Lower Body Strength',
    description: 'Squats and Romanian Deadlifts',
    startTime: new Date(todayYear, todayMonth, todayDate - 3, 16, 0).toISOString(),
    endTime: new Date(todayYear, todayMonth, todayDate - 3, 17, 10).toISOString(),
    exercises: [
      {
        index: 0,
        title: 'Barbell Back Squat',
        sets: [
          { index: 0, type: 'normal', weightKg: 90, reps: 5 },
          { index: 1, type: 'normal', weightKg: 95, reps: 5 },
          { index: 2, type: 'normal', weightKg: 100, reps: 4 },
        ],
      },
    ],
  },
];
