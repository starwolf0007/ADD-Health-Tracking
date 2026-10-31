import React, { useState } from 'react';
import { Sparkles, Brain, CheckCircle2, Moon, Target, Shuffle } from 'lucide-react';

export type LexiVisualState = 'idle' | 'focus' | 'thinking' | 'transition' | 'success' | 'evening';

interface LexiAvatarProps {
  visualState?: LexiVisualState;
  size?: number;
  subtleIdleAnimation?: boolean;
  className?: string;
}

export const LexiAvatar: React.FC<LexiAvatarProps> = ({
  visualState = 'idle',
  size = 44,
  subtleIdleAnimation = true,
  className = '',
}) => {
  const [imageError, setImageError] = useState(false);

  const getStatusIcon = () => {
    switch (visualState) {
      case 'focus':
        return <Target className="w-3.5 h-3.5 text-[#2FB083]" />;
      case 'thinking':
        return <Sparkles className="w-3.5 h-3.5 text-[#BB86FC]" />;
      case 'transition':
        return <Shuffle className="w-3.5 h-3.5 text-[#D9A441]" />;
      case 'success':
        return <CheckCircle2 className="w-3.5 h-3.5 text-[#2FB083]" />;
      case 'evening':
        return <Moon className="w-3.5 h-3.5 text-[#BB86FC]" />;
      case 'idle':
      default:
        return <Brain className="w-3.5 h-3.5 text-[#BB86FC]" />;
    }
  };

  return (
    <div
      className={`relative inline-flex items-center justify-center shrink-0 ${
        subtleIdleAnimation ? 'animate-lexi-breathe' : ''
      } ${className}`}
      style={{ width: size, height: size }}
      title={`Lexi (${visualState})`}
    >
      <div
        className="w-full h-full rounded-full overflow-hidden border border-[#232326] bg-[#1C1C1F] flex items-center justify-center shadow-md"
        style={{ width: size, height: size }}
      >
        {!imageError ? (
          <img
            src="/assets/lexi/public/lexi-canonical-face.jpg"
            alt="Lexi companion"
            className="w-full h-full object-cover"
            onError={() => setImageError(true)}
          />
        ) : (
          <div className="w-full h-full bg-gradient-to-br from-[#1E7A5A] to-[#1C1C1F] flex items-center justify-center text-[#F0F0F0]">
            <Brain className="w-1/2 h-1/2 text-[#BB86FC]" />
          </div>
        )}
      </div>

      {/* Visual State badge */}
      <span className="absolute -bottom-0.5 -right-0.5 w-4 h-4 rounded-full bg-[#161618] border border-[#232326] flex items-center justify-center shadow-sm">
        {getStatusIcon()}
      </span>
    </div>
  );
};
