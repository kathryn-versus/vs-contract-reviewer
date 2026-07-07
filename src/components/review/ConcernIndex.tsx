import { STANDING_CONCERNS, CONCERN_SHORT_LABELS as SHORT_LABELS } from '@/lib/types';

/**
 * The standing concerns shown as a persistent reference strip, so it's
 * clear what was checked regardless of how many issues were actually flagged.
 */
export function ConcernIndex() {
  return (
    <div className="flex flex-wrap gap-x-4 gap-y-1.5 border-b-2 border-ink pb-4 font-mono text-xs text-ink-soft">
      {STANDING_CONCERNS.map((c, i) => (
        <span key={c.id} className="whitespace-nowrap">
          <span className="font-medium text-ink">{c.id}.</span> {SHORT_LABELS[c.id] ?? c.label}
          {i < STANDING_CONCERNS.length - 1 && <span className="ml-4 text-rule">|</span>}
        </span>
      ))}
    </div>
  );
}
