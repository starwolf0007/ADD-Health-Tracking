import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  Play,
  Pause,
  RotateCcw,
  Volume2,
  VolumeX,
  X,
  Maximize2,
  Minimize2,
  CheckCircle2,
  Clock,
  Sparkles,
  Zap,
} from 'lucide-react';
import { Task } from '../types';
import { taskStorage } from '../lib/storage';

interface VisualClockTimerProps {
  initialMinutes?: number;
  activeTask?: Task | null;
  onClose?: () => void;
  onTaskCompleted?: (taskId: string) => void;
  isFloating?: boolean;
}

// Gentle Web Audio API chime generator (soft bell/marimba sound for ADHD friendly alerts)
function playGentleChime(type: 'complete' | 'tick') {
  try {
    const AudioContextClass = window.AudioContext || (window as any).webkitAudioContext;
    if (!AudioContextClass) return;
    const ctx = new AudioContextClass();

    if (type === 'tick') {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(600, ctx.currentTime);
      gain.gain.setValueAtTime(0.015, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.04);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start();
      osc.stop(ctx.currentTime + 0.05);
      return;
    }

    // Complete chime: multi-harmonic calm triad (E5, G#5, B5)
    const notes = [659.25, 830.61, 987.77];
    notes.forEach((freq, i) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'triangle';
      osc.frequency.setValueAtTime(freq, ctx.currentTime + i * 0.12);

      gain.gain.setValueAtTime(0.12, ctx.currentTime + i * 0.12);
      gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + i * 0.12 + 1.2);

      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(ctx.currentTime + i * 0.12);
      osc.stop(ctx.currentTime + i * 0.12 + 1.3);
    });
  } catch {}
}

export const VisualClockTimer: React.FC<VisualClockTimerProps> = ({
  initialMinutes = 25,
  activeTask = null,
  onClose,
  onTaskCompleted,
  isFloating = false,
}) => {
  const [targetMinutes, setTargetMinutes] = useState<number>(initialMinutes);
  const [totalSeconds, setTotalSeconds] = useState<number>(initialMinutes * 60);
  const [remainingSeconds, setRemainingSeconds] = useState<number>(initialMinutes * 60);
  const [isRunning, setIsRunning] = useState<boolean>(false);
  const [isMuted, setIsMuted] = useState<boolean>(false);
  const [soundTick, setSoundTick] = useState<boolean>(false);
  const [isOvertime, setIsOvertime] = useState<boolean>(false);
  const [overtimeSeconds, setOvertimeSeconds] = useState<number>(0);
  const [isFullScreen, setIsFullScreen] = useState<boolean>(false);

  // Time spent in current session (seconds)
  const [elapsedSeconds, setElapsedSeconds] = useState<number>(0);

  // Interval ref
  const timerRef = useRef<number | null>(null);

  // Handle Preset Selection (5m, 25m, 50m)
  const handleSelectPreset = (mins: number) => {
    setIsRunning(false);
    setIsOvertime(false);
    setOvertimeSeconds(0);
    setTargetMinutes(mins);
    setTotalSeconds(mins * 60);
    setRemainingSeconds(mins * 60);
    setElapsedSeconds(0);
  };

  // Timer Tick Logic
  useEffect(() => {
    if (isRunning) {
      timerRef.current = window.setInterval(() => {
        setElapsedSeconds((prev) => prev + 1);

        if (soundTick && !isMuted) {
          playGentleChime('tick');
        }

        setRemainingSeconds((prev) => {
          if (prev <= 1) {
            // Reached zero: transition into gentle overtime flow rather than abrupt stop!
            if (!isOvertime) {
              setIsOvertime(true);
              if (!isMuted) playGentleChime('complete');
            }
            return 0;
          }
          return prev - 1;
        });

        if (isOvertime) {
          setOvertimeSeconds((prev) => prev + 1);
        }
      }, 1000);
    } else {
      if (timerRef.current) clearInterval(timerRef.current);
    }

    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [isRunning, isOvertime, soundTick, isMuted]);

  const handleReset = () => {
    setIsRunning(false);
    setIsOvertime(false);
    setOvertimeSeconds(0);
    setRemainingSeconds(targetMinutes * 60);
    setElapsedSeconds(0);
  };

  const handleCompleteTask = () => {
    if (activeTask) {
      taskStorage.complete(activeTask.id);
      if (onTaskCompleted) onTaskCompleted(activeTask.id);
    }
    if (!isMuted) playGentleChime('complete');
    setIsRunning(false);
  };

  // -------------------------------------------------------------------------
  // SVG Visual Clock Calculations
  // Center: 150, 150 | Radius: 105
  // Total dial is 60 minutes.
  // -------------------------------------------------------------------------
  const cx = 150;
  const cy = 150;
  const r = 100;

  // Fraction of 60 minutes dial
  // In a traditional Time Timer / visual clock, the colored wedge represents REMAINING time.
  const remainingMinutesFraction = remainingSeconds / 3600; // out of 60 mins
  const remainingAngleDeg = Math.min(359.99, remainingMinutesFraction * 360);

  // Elapsed wedge angle (representing time actually spent so far)
  const elapsedMinutesFraction = (elapsedSeconds % 3600) / 3600;
  const elapsedAngleDeg = Math.min(359.99, elapsedMinutesFraction * 360);

  // SVG Arc generator from 0 deg (12 o'clock) to angleDeg clockwise
  const describeArc = (startAngle: number, endAngle: number, radius: number) => {
    const startRad = ((startAngle - 90) * Math.PI) / 180.0;
    const endRad = ((endAngle - 90) * Math.PI) / 180.0;

    const x1 = cx + radius * Math.cos(startRad);
    const y1 = cy + radius * Math.sin(startRad);
    const x2 = cx + radius * Math.cos(endRad);
    const y2 = cy + radius * Math.sin(endRad);

    const largeArcFlag = endAngle - startAngle <= 180 ? '0' : '1';

    return `M ${cx} ${cy} L ${x1} ${y1} A ${radius} ${radius} 0 ${largeArcFlag} 1 ${x2} ${y2} Z`;
  };

  // Clock ticks (60 minute marks)
  const ticks = Array.from({ length: 60 }).map((_, i) => {
    const isMajor = i % 5 === 0;
    const angle = (i * 6 - 90) * (Math.PI / 180);
    const innerR = isMajor ? r - 12 : r - 6;
    const outerR = r;
    const x1 = cx + innerR * Math.cos(angle);
    const y1 = cy + innerR * Math.sin(angle);
    const x2 = cx + outerR * Math.cos(angle);
    const y2 = cy + outerR * Math.sin(angle);

    // Number label for 0, 5, 10, 15, ..., 55
    const textR = r - 22;
    const textX = cx + textR * Math.cos(angle);
    const textY = cy + textR * Math.sin(angle);

    return {
      id: i,
      x1,
      y1,
      x2,
      y2,
      isMajor,
      number: isMajor ? (i === 0 ? '60' : String(i)) : null,
      textX,
      textY,
    };
  });

  // Hand angle in degrees (0 = 12 o'clock)
  const handAngle = (remainingMinutesFraction * 360);
  const handRad = ((handAngle - 90) * Math.PI) / 180.0;
  const handX = cx + (r - 10) * Math.cos(handRad);
  const handY = cy + (r - 10) * Math.sin(handRad);

  // Minutes and seconds formatting
  const displayMins = Math.floor(remainingSeconds / 60);
  const displaySecs = remainingSeconds % 60;
  const timeFormatted = `${String(displayMins).padStart(2, '0')}:${String(displaySecs).padStart(2, '0')}`;

  const elapsedMins = Math.floor(elapsedSeconds / 60);
  const elapsedSecs = elapsedSeconds % 60;
  const elapsedFormatted = `${elapsedMins}m ${elapsedSecs}s spent`;

  // Color dynamics: emerald (#2FB083) normally; soft amber (#D9A441) when under 3 mins; gold (#FFD700) in overtime
  const wedgeColor = isOvertime
    ? '#FFD700'
    : remainingSeconds <= 180
    ? '#D9A441'
    : targetMinutes === 5
    ? '#7AA7A0'
    : targetMinutes === 50
    ? '#388E3C'
    : '#2FB083';

  return (
    <div
      className={`bg-[#161618] border border-[#232326] rounded-3xl p-5 shadow-2xl flex flex-col items-center select-none transition-all ${
        isFullScreen
          ? 'fixed inset-0 z-50 rounded-none max-w-none justify-center'
          : 'w-full max-w-md mx-auto'
      }`}
    >
      {/* Top Header */}
      <div className="w-full flex items-center justify-between pb-3 border-b border-[#232326] mb-4">
        <div className="flex items-center gap-2">
          <div className="p-1.5 rounded-lg bg-[#2FB083]/15 text-[#2FB083]">
            <Clock className="w-4 h-4" />
          </div>
          <div>
            <h3 className="text-sm font-semibold text-[#F0F0F0]">Visual Clock Timer</h3>
            <p className="text-[11px] text-[#8A8A8E]">ADHD Time-Blindness Companion</p>
          </div>
        </div>

        <div className="flex items-center gap-1.5">
          {/* Tick Sound Toggle */}
          <button
            onClick={() => setSoundTick(!soundTick)}
            className={`p-1.5 rounded-lg border text-xs transition-colors ${
              soundTick
                ? 'bg-[#2FB083]/20 text-[#2FB083] border-[#2FB083]/40'
                : 'bg-[#1C1C1F] text-[#8A8A8E] border-[#232326]'
            }`}
            title={soundTick ? 'Tick sound ON (auditory pacing)' : 'Tick sound OFF'}
          >
            {soundTick ? <Volume2 className="w-3.5 h-3.5" /> : <VolumeX className="w-3.5 h-3.5" />}
          </button>

          {/* Fullscreen Expand */}
          <button
            onClick={() => setIsFullScreen(!isFullScreen)}
            className="p-1.5 text-[#8A8A8E] hover:text-[#F0F0F0] rounded-lg border border-[#232326] hover:bg-[#1C1C1F]"
            title={isFullScreen ? 'Exit full screen' : 'Expand full screen'}
          >
            {isFullScreen ? <Minimize2 className="w-3.5 h-3.5" /> : <Maximize2 className="w-3.5 h-3.5" />}
          </button>

          {onClose && (
            <button
              onClick={onClose}
              className="p-1.5 text-[#8A8A8E] hover:text-[#F0F0F0] rounded-lg border border-[#232326] hover:bg-[#1C1C1F]"
            >
              <X className="w-4 h-4" />
            </button>
          )}
        </div>
      </div>

      {/* Preset Duration Selector: 5 min, 25 min, 50 min */}
      <div className="grid grid-cols-3 gap-2 w-full mb-4">
        <button
          onClick={() => handleSelectPreset(5)}
          className={`py-2 px-3 rounded-xl border text-xs font-semibold flex flex-col items-center transition-all ${
            targetMinutes === 5
              ? 'bg-[#2FB083]/20 text-[#2FB083] border-[#2FB083] shadow-md shadow-[#2FB083]/15'
              : 'bg-[#1C1C1F] text-[#8A8A8E] border-[#232326] hover:text-[#F0F0F0]'
          }`}
        >
          <span className="text-sm font-bold">5 min</span>
          <span className="text-[10px] opacity-75 font-normal">Micro-Sprint</span>
        </button>

        <button
          onClick={() => handleSelectPreset(25)}
          className={`py-2 px-3 rounded-xl border text-xs font-semibold flex flex-col items-center transition-all ${
            targetMinutes === 25
              ? 'bg-[#2FB083]/20 text-[#2FB083] border-[#2FB083] shadow-md shadow-[#2FB083]/15'
              : 'bg-[#1C1C1F] text-[#8A8A8E] border-[#232326] hover:text-[#F0F0F0]'
          }`}
        >
          <span className="text-sm font-bold">25 min</span>
          <span className="text-[10px] opacity-75 font-normal">Pomodoro Focus</span>
        </button>

        <button
          onClick={() => handleSelectPreset(50)}
          className={`py-2 px-3 rounded-xl border text-xs font-semibold flex flex-col items-center transition-all ${
            targetMinutes === 50
              ? 'bg-[#2FB083]/20 text-[#2FB083] border-[#2FB083] shadow-md shadow-[#2FB083]/15'
              : 'bg-[#1C1C1F] text-[#8A8A8E] border-[#232326] hover:text-[#F0F0F0]'
          }`}
        >
          <span className="text-sm font-bold">50 min</span>
          <span className="text-[10px] opacity-75 font-normal">Deep Immersion</span>
        </button>
      </div>

      {/* Active Task Banner if bound */}
      {activeTask && (
        <div className="w-full bg-[#1C1C1F] border border-[#232326] rounded-xl px-3 py-2 mb-3 flex items-center justify-between">
          <div className="truncate mr-2">
            <span className="text-[10px] font-semibold text-[#2FB083] uppercase block">
              Focused Task
            </span>
            <span className="text-xs font-medium text-[#F0F0F0] truncate block">
              {activeTask.title}
            </span>
          </div>
          <button
            onClick={handleCompleteTask}
            className="flex items-center gap-1 px-2.5 py-1 rounded-lg bg-[#2FB083]/15 hover:bg-[#2FB083]/25 text-[#2FB083] text-xs font-medium border border-[#2FB083]/30 shrink-0 transition-colors"
          >
            <CheckCircle2 className="w-3.5 h-3.5" />
            <span>Done</span>
          </button>
        </div>
      )}

      {/* Actual Clock Graphic: Physical Moving Disk & Hand */}
      <div className="relative my-2 flex items-center justify-center">
        <svg
          viewBox="0 0 300 300"
          className="w-64 h-64 sm:w-72 sm:h-72 drop-shadow-xl filter"
        >
          {/* Outer Clock Case */}
          <circle
            cx={cx}
            cy={cy}
            r={r + 28}
            className="fill-[#1A1A1D] stroke-[#2A2A2E] stroke-2"
          />
          <circle
            cx={cx}
            cy={cy}
            r={r + 20}
            className="fill-[#121214] stroke-[#232326] stroke-1"
          />

          {/* Clock Dial Background Face */}
          <circle
            cx={cx}
            cy={cy}
            r={r}
            className="fill-[#0C0C0D] stroke-[#232326] stroke-1"
          />

          {/* Elapsed Time Wedge (Shows time spent so far as a subtle ghost ring) */}
          {elapsedAngleDeg > 0 && !isOvertime && (
            <path
              d={describeArc(0, elapsedAngleDeg, r - 2)}
              fill="#2FB083"
              fillOpacity="0.12"
            />
          )}

          {/* Remaining Time Disk Wedge (The famous Time Timer visual colored sector) */}
          {remainingAngleDeg > 0 && (
            <path
              d={describeArc(0, remainingAngleDeg, r - 2)}
              fill={wedgeColor}
              fillOpacity={isOvertime ? '0.4' : '0.85'}
              className="transition-all duration-300"
            />
          )}

          {/* Overtime Ring Pulse */}
          {isOvertime && (
            <circle
              cx={cx}
              cy={cy}
              r={r - 4}
              fill="none"
              stroke="#FFD700"
              strokeWidth="4"
              strokeDasharray="6 4"
              className="animate-spin"
              style={{ animationDuration: '10s' }}
            />
          )}

          {/* Dial Minute Ticks and Number Labels */}
          {ticks.map((t) => (
            <React.Fragment key={t.id}>
              <line
                x1={t.x1}
                y1={t.y1}
                x2={t.x2}
                y2={t.y2}
                stroke={t.isMajor ? '#8A8A8E' : '#333336'}
                strokeWidth={t.isMajor ? 2 : 1}
              />
              {t.number && (
                <text
                  x={t.textX}
                  y={t.textY}
                  textAnchor="middle"
                  dominantBaseline="central"
                  fontSize="10"
                  fontFamily="monospace"
                  fill="#8A8A8E"
                  fontWeight="600"
                >
                  {t.number}
                </text>
              )}
            </React.Fragment>
          ))}

          {/* Physical Sweeping Hand */}
          <line
            x1={cx}
            y1={cy}
            x2={handX}
            y2={handY}
            stroke="#F0F0F0"
            strokeWidth="2.5"
            strokeLinecap="round"
            className="transition-all duration-300 drop-shadow-md"
          />

          {/* Clock Center Hub */}
          <circle cx={cx} cy={cy} r="18" fill="#1C1C1F" stroke="#333336" strokeWidth="2" />
          <circle cx={cx} cy={cy} r="5" fill={wedgeColor} />
        </svg>

        {/* Digital Time Overlay in Center */}
        <div className="absolute flex flex-col items-center justify-center pointer-events-none mt-20">
          <span
            className={`font-mono text-2xl font-bold tracking-tight drop-shadow-md ${
              isOvertime ? 'text-[#FFD700] animate-pulse' : 'text-[#F0F0F0]'
            }`}
          >
            {isOvertime ? `+${Math.floor(overtimeSeconds / 60)}:${String(overtimeSeconds % 60).padStart(2, '0')}` : timeFormatted}
          </span>
          <span className="text-[10px] text-[#8A8A8E] font-medium tracking-wider uppercase mt-0.5">
            {isOvertime ? 'Bonus Flow' : isRunning ? 'In Progress' : 'Paused'}
          </span>
        </div>
      </div>

      {/* Time Spent Statistics Indicator ("so I can tell how long I've actually spent") */}
      <div className="flex items-center gap-2 text-xs text-[#8A8A8E] mt-2 mb-4 bg-[#121214] px-3 py-1.5 rounded-full border border-[#232326]">
        <Zap className="w-3.5 h-3.5 text-[#2FB083]" />
        <span>Actually spent on task:</span>
        <span className="font-mono text-[#F0F0F0] font-semibold">{elapsedFormatted}</span>
      </div>

      {/* Controls: Play/Pause, Reset, Complete */}
      <div className="flex items-center gap-3 w-full justify-center">
        <button
          onClick={handleReset}
          className="p-3 rounded-2xl bg-[#1C1C1F] hover:bg-[#232326] text-[#8A8A8E] hover:text-[#F0F0F0] border border-[#232326] transition-colors"
          title="Reset Timer"
        >
          <RotateCcw className="w-5 h-5" />
        </button>

        <button
          onClick={() => setIsRunning(!isRunning)}
          className={`flex-1 max-w-[180px] py-3.5 px-6 rounded-2xl font-semibold text-sm flex items-center justify-center gap-2 shadow-lg transition-all active:scale-95 ${
            isRunning
              ? 'bg-[#D9A441] text-[#0C0C0D] hover:bg-[#D9A441]/90 shadow-[#D9A441]/20'
              : 'bg-[#2FB083] text-[#0C0C0D] hover:bg-[#2FB083]/90 shadow-[#2FB083]/25'
          }`}
        >
          {isRunning ? (
            <>
              <Pause className="w-5 h-5 fill-current" />
              <span>Pause</span>
            </>
          ) : (
            <>
              <Play className="w-5 h-5 fill-current" />
              <span>{remainingSeconds === totalSeconds ? 'Start' : 'Resume'}</span>
            </>
          )}
        </button>

        <button
          onClick={handleCompleteTask}
          className="p-3 rounded-2xl bg-[#1C1C1F] hover:bg-[#2FB083]/20 text-[#8A8A8E] hover:text-[#2FB083] border border-[#232326] hover:border-[#2FB083]/40 transition-colors"
          title="Mark task completed"
        >
          <CheckCircle2 className="w-5 h-5" />
        </button>
      </div>
    </div>
  );
};
