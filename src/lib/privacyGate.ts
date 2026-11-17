import { Habit } from '../types';

/**
 * Deterministic Sensitive-Data Gate & On-Device-Only Privacy Boundary
 * Per NeuroFlow Unified Spec v1.4 (§2.8, §14) & HEALTH_PHASE1_DATA_SPEC (§2):
 * - MoodLog, energy state logs, medication habits, and Hevy/health metrics belong to
 *   the sensitive class.
 * - Sensitive data is strictly local-first / on-device-only:
 *   1. Never transmitted to Cloud AI (/api/gemini/*).
 *   2. Never synced to Cloud Firestore.
 *   3. Excluded by default from exports and automatic Google Drive backups unless
 *      the user explicitly opts in during a manual backup export.
 */

const MEDICATION_KEYWORDS_REGEX =
  /\b(medication|medicine|meds|pill|pills|dose|dosage|prescription|rx|adderall|vyvanse|ritalin|concerta|focalin|strattera|wellbutrin|lexapro|zoloft|prozac|ssri|stimulant|capsule|tablet|mg\s+dose)\b/i;

const SENSITIVE_TEXT_PATTERNS: Array<{
  category: 'mood' | 'medication' | 'health_metric' | 'energy_state';
  pattern: RegExp;
  replacement: string;
}> = [
  {
    category: 'medication',
    pattern:
      /\b(took\s+my\s+(?:meds|medication|pills?|dose)|(?:adderall|vyvanse|ritalin|concerta|focalin|strattera|wellbutrin|lexapro|zoloft|prozac)\s*(?:\d+\s*mg)?|\d+\s*mg\s+(?:dose|pill|tablet|capsule|meds?|medication))\b/gi,
    replacement: '[ON-DEVICE MEDICATION DATA REDACTED]',
  },
  {
    category: 'mood',
    pattern:
      /\b(mood\s*log\s*[:=-]\s*[^\n.,;]+|mood\s*score\s*[:=-]?\s*[1-5]|logged\s+mood\s*[:=-]?\s*(?:great|good|okay|low|struggling))\b/gi,
    replacement: '[ON-DEVICE MOOD LOG REDACTED]',
  },
  {
    category: 'health_metric',
    pattern:
      /\b(hrv\s*[:=-]?\s*\d+\s*(?:ms)?|resting\s+heart\s+rate\s*[:=-]?\s*\d+\s*(?:bpm)?|blood\s+pressure\s*[:=-]?\s*\d+\/\d+|hevy\s+workout\s+log\s*[:=-][^\n.]+)\b/gi,
    replacement: '[ON-DEVICE HEALTH METRIC REDACTED]',
  },
  {
    category: 'energy_state',
    pattern:
      /\b(energy\s*log\s*[:=-]\s*(?:low|medium|high|depleted|exhausted|wired))\b/gi,
    replacement: '[ON-DEVICE ENERGY LOG REDACTED]',
  },
];

const SENSITIVE_CONTEXT_KEYS = new Set([
  'mood',
  'moods',
  'moodlog',
  'moodlogs',
  'currentmood',
  'energystate',
  'energylog',
  'hevy',
  'hevyworkouts',
  'workouts',
  'healthmetrics',
  'healthconnect',
  'medications',
  'medicationlogs',
]);

/**
 * Determines whether a habit belongs to the sensitive medication class.
 */
export function isMedicationHabit(
  habitOrName: Pick<Habit, 'name' | 'icon'> | string | null | undefined
): boolean {
  if (!habitOrName) return false;
  if (typeof habitOrName === 'string') {
    return habitOrName.includes('💊') || MEDICATION_KEYWORDS_REGEX.test(habitOrName);
  }
  const icon = habitOrName.icon || '';
  const name = habitOrName.name || '';
  return icon.includes('💊') || name.includes('💊') || MEDICATION_KEYWORDS_REGEX.test(name);
}

/**
 * Filters a list of habits to exclude sensitive medication-class habits.
 */
export function filterNonSensitiveHabits<T extends { name: string; icon?: string }>(
  habits: T[]
): T[] {
  if (!Array.isArray(habits)) return [];
  return habits.filter((h) => !isMedicationHabit(h));
}

/**
 * Inspects text and redacts sensitive on-device-only health/mood/medication tokens
 * before sending any prompt to Cloud AI.
 */
export function redactSensitiveText(input: string): {
  sanitizedText: string;
  wasRedacted: boolean;
  redactedCategories: Array<'mood' | 'medication' | 'health_metric' | 'energy_state'>;
} {
  if (typeof input !== 'string' || !input) {
    return { sanitizedText: '', wasRedacted: false, redactedCategories: [] };
  }

  let sanitizedText = input;
  const categories = new Set<'mood' | 'medication' | 'health_metric' | 'energy_state'>();

  for (const rule of SENSITIVE_TEXT_PATTERNS) {
    rule.pattern.lastIndex = 0;
    if (rule.pattern.test(sanitizedText)) {
      categories.add(rule.category);
      rule.pattern.lastIndex = 0;
      sanitizedText = sanitizedText.replace(rule.pattern, rule.replacement);
    }
  }

  return {
    sanitizedText,
    wasRedacted: categories.size > 0,
    redactedCategories: Array.from(categories),
  };
}

/**
 * Strips any sensitive fields or medication habits from a context object
 * before it is attached to a Cloud AI request.
 */
export function sanitizeContextForCloudAi(
  context: Record<string, any> | null | undefined
): Record<string, any> {
  if (!context || typeof context !== 'object') {
    return {};
  }

  const safeContext: Record<string, any> = {};

  for (const [key, value] of Object.entries(context)) {
    const normalizedKey = key.toLowerCase().replace(/[^a-z0-9]/g, '');
    if (SENSITIVE_CONTEXT_KEYS.has(normalizedKey)) {
      continue;
    }

    if (key === 'habits' && Array.isArray(value)) {
      safeContext[key] = filterNonSensitiveHabits(value);
      continue;
    }

    if (typeof value === 'string') {
      safeContext[key] = redactSensitiveText(value).sanitizedText;
    } else if (Array.isArray(value)) {
      safeContext[key] = value.map((item) =>
        typeof item === 'string' ? redactSensitiveText(item).sanitizedText : item
      );
    } else {
      safeContext[key] = value;
    }
  }

  return safeContext;
}
