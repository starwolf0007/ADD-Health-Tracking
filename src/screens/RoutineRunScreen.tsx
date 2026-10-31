import React, { useState, useEffect } from 'react';
import { X, CheckCircle2, Clock, Check, ChevronRight } from 'lucide-react';
import { Routine, RoutineStep } from '../types';
import { routineStorage } from '../lib/storage';

interface RoutineRunScreenProps {
  routine: Routine;
  onFinished: () => void;
  refresh: () => void;
}

export const RoutineRunScreen: React.FC<RoutineRunScreenProps> = ({
  routine,
  onFinished,
  refresh,
}) => {
  const [steps, setSteps] = useState<RoutineStep[]>(() =>
    [...routine.steps].sort((a, b) => a.position - b.position)
  );
  const [showCelebration, setShowCelebration] = useState(false);

  const completedCount = steps.filter((s) => s.isComplete).length;
  const totalCount = steps.length;
  const progressFraction = totalCount === 0 ? 0 : completedCount / totalCount;

  // Active step is the first non-completed step by position
  const activeStep = steps.find((s) => !s.isComplete) || null;
  const upNextSteps = steps.filter((s) => !s.isComplete && s.id !== activeStep?.id);

  const handleCompleteStep = (stepId: string) => {
    const updatedSteps = steps.map((s) =>
      s.id === stepId ? { ...s, isComplete: true } : s
    );
    setSteps(updatedSteps);

    const stepObj = updatedSteps.find((s) => s.id === stepId);
    if (stepObj) {
      routineStorage.updateStep(routine.id, stepObj);
    }

    const nextCompletedCount = updatedSteps.filter((s) => s.isComplete).length;
    if (nextCompletedCount >= totalCount) {
      setShowCelebration(true);
      setTimeout(() => {
        refresh();
        onFinished();
      }, 2200);
    }
  };

  const handleSkipStep = (stepId: string) => {
    // Skip = mark complete without ceremony. No guilt.
    handleCompleteStep(stepId);
  };

  const handleReset = () => {
    routineStorage.resetRoutineSteps(routine.id);
    setSteps(steps.map((s) => ({ ...s, isComplete: false })));
    refresh();
  };

  if (showCelebration) {
    return (
      <div className="fixed inset-0 z-50 bg-[#0C0C0D] flex flex-col items-center justify-center p-6 text-center animate-in fade-in duration-300">
        <div className="w-20 h-20 rounded-full bg-[#2FB083]/20 flex items-center justify-center mb-6 animate-bounce">
          <CheckCircle2 className="w-12 h-12 text-[#2FB083]" />
        </div>
        <h2 className="text-2xl font-light text-[#F0F0F0] mb-2">{routine.name}</h2>
        <p className="text-sm font-medium text-[#2FB083] uppercase tracking-wider">
          Routine Complete
        </p>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-50 bg-[#0C0C0D] flex flex-col max-w-2xl mx-auto shadow-2xl">
      {/* Header */}
      <div className="p-4 flex items-center justify-between border-b border-[#232326]">
        <button
          onClick={onFinished}
          className="p-1.5 text-[#8A8A8E] hover:text-[#F0F0F0] rounded-xl"
          title="Exit routine"
        >
          <X className="w-5 h-5" />
        </button>

        <h3 className="text-sm font-medium text-[#F0F0F0] truncate max-w-[200px]">
          {routine.name}
        </h3>

        <div className="flex items-center gap-2">
          <span className="text-xs font-mono text-[#8A8A8E]">
            {completedCount}/{totalCount}
          </span>
          {completedCount > 0 && (
            <button
              onClick={handleReset}
              className="text-[11px] text-[#555559] hover:text-[#8A8A8E] underline ml-1"
            >
              Reset
            </button>
          )}
        </div>
      </div>

      {/* Progress Bar (Updates on step transition only - §13 no ambient animation) */}
      <div className="w-full h-1 bg-[#212124]">
        <div
          className="h-full bg-[#2FB083] transition-all duration-300"
          style={{ width: `${Math.min(100, progressFraction * 100)}%` }}
        />
      </div>

      {/* Main Focus Area - surfaces ONE step at a time */}
      <div className="flex-1 flex flex-col justify-between p-6 sm:p-8">
        {activeStep ? (
          <>
            <div className="space-y-4 pt-4">
              <span className="text-xs font-medium text-[#8A8A8E] tracking-wider uppercase">
                Step {completedCount + 1} of {totalCount}
              </span>

              <h1 className="text-2xl sm:text-3xl font-light text-[#F0F0F0] leading-tight tracking-tight">
                {activeStep.title}
              </h1>

              {activeStep.notes && (
                <p className="text-sm text-[#8A8A8E] leading-relaxed max-w-md">
                  {activeStep.notes}
                </p>
              )}

              {activeStep.durationMinutes && (
                <div className="flex items-center gap-1.5 text-xs font-mono text-[#555559] pt-2">
                  <Clock className="w-3.5 h-3.5" />
                  <span>{activeStep.durationMinutes} min estimated</span>
                </div>
              )}
            </div>

            {/* Action Buttons */}
            <div className="space-y-3 pt-8">
              <button
                onClick={() => handleCompleteStep(activeStep.id)}
                className="w-full py-4 bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] rounded-2xl text-base font-semibold shadow-lg shadow-[#2FB083]/15 transition-all active:scale-[0.99] flex items-center justify-center gap-2"
              >
                <Check className="w-5 h-5 stroke-[2.5]" />
                <span>Done</span>
              </button>

              <div className="text-center">
                <button
                  onClick={() => handleSkipStep(activeStep.id)}
                  className="text-xs text-[#555559] hover:text-[#8A8A8E] py-2 transition-colors"
                >
                  Skip this step (no judgement)
                </button>
              </div>
            </div>
          </>
        ) : (
          <div className="text-center my-auto py-12">
            <CheckCircle2 className="w-12 h-12 text-[#2FB083] mx-auto mb-3" />
            <h2 className="text-lg font-medium text-[#F0F0F0]">All steps complete!</h2>
            <button
              onClick={onFinished}
              className="mt-4 px-6 py-2.5 bg-[#212124] text-xs font-semibold rounded-xl text-[#F0F0F0]"
            >
              Back to Routines
            </button>
          </div>
        )}
      </div>

      {/* Up Next List (De-emphasized preview) */}
      {upNextSteps.length > 0 && (
        <div className="p-4 border-t border-[#232326] bg-[#161618]/50">
          <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block mb-2">
            Up Next
          </span>
          <div className="space-y-1.5">
            {upNextSteps.slice(0, 3).map((step) => (
              <div
                key={step.id}
                className="flex items-center gap-2 text-xs text-[#8A8A8E] truncate"
              >
                <span className="text-[#555559]">·</span>
                <span className="truncate">{step.title}</span>
              </div>
            ))}
            {upNextSteps.length > 3 && (
              <span className="text-[11px] text-[#555559] block pt-0.5">
                + {upNextSteps.length - 3} more
              </span>
            )}
          </div>
        </div>
      )}
    </div>
  );
};
