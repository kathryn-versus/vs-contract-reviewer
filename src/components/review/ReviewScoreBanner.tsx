'use client';

import type { Finding } from '@/lib/types';
import { computeReviewScore } from '@/lib/report/scoring';

const GRADE_COLOR: Record<string, string> = {
  A: 'text-low',
  B: 'text-low',
  C: 'text-med',
  D: 'text-high',
  F: 'text-high',
};

export function ReviewScoreBanner({ findings }: { findings: Finding[] }) {
  const { grade, summary } = computeReviewScore(findings);
  return (
    <div className="flex items-center gap-4 rounded-sm border border-rule bg-paper px-5 py-4">
      <span className={`font-display text-4xl ${GRADE_COLOR[grade]}`}>{grade}</span>
      <p className="font-body text-sm text-ink-soft">{summary}</p>
    </div>
  );
}
