'use client';

import clsx from 'clsx';
import type { Finding, Severity } from '@/lib/types';

export type FilterValue = 'all' | Severity;

export function SeveritySummary({
  findings,
  active,
  onChange,
}: {
  findings: Finding[];
  active: FilterValue;
  onChange: (v: FilterValue) => void;
}) {
  const counts = {
    all: findings.length,
    high: findings.filter((f) => f.severity === 'high').length,
    medium: findings.filter((f) => f.severity === 'medium').length,
    low: findings.filter((f) => f.severity === 'low').length,
  };

  const cards: { key: FilterValue; label: string }[] = [
    { key: 'all', label: 'Total flagged' },
    { key: 'high', label: 'High' },
    { key: 'medium', label: 'Medium' },
    { key: 'low', label: 'Low' },
  ];

  return (
    <div className="grid grid-cols-4 gap-3">
      {cards.map((c) => (
        <button
          key={c.key}
          onClick={() => onChange(c.key)}
          className={clsx(
            'rounded-sm border px-4 py-4 text-left transition',
            active === c.key
              ? 'border-ink bg-ink text-paper'
              : 'border-rule bg-paper text-ink hover:border-ink-faint'
          )}
        >
          <p className="font-display text-2xl">{counts[c.key]}</p>
          <p
            className={clsx(
              'mt-1 font-mono text-[11px] uppercase tracking-wide',
              active === c.key ? 'text-paper/70' : 'text-ink-faint'
            )}
          >
            {c.label}
          </p>
        </button>
      ))}
    </div>
  );
}
