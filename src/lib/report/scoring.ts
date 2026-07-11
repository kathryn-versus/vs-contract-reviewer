import type { Finding } from '@/lib/types';

export interface ReviewScore {
  score: number; // 0-100
  grade: 'A' | 'B' | 'C' | 'D' | 'F';
  summary: string;
}

/**
 * A quick, deterministic scan-friendly signal — NOT a legal risk model.
 * Highs cost the most, lows barely move the needle. Shared by the in-app
 * results view and both exported report formats so the grade/summary are
 * always consistent across all three.
 */
export function computeReviewScore(findings: Finding[]): ReviewScore {
  const high = findings.filter((f) => f.severity === 'high').length;
  const medium = findings.filter((f) => f.severity === 'medium').length;
  const low = findings.filter((f) => f.severity === 'low').length;

  const score = Math.max(0, Math.min(100, 100 - (high * 15 + medium * 7 + low * 2)));

  const grade: ReviewScore['grade'] =
    score >= 90 ? 'A' : score >= 80 ? 'B' : score >= 65 ? 'C' : score >= 45 ? 'D' : 'F';

  let summary: string;
  if (findings.length === 0) {
    summary = 'No issues found against the standing concerns.';
  } else if (high === 0 && medium === 0) {
    summary = `Generally aligned with standard terms — only ${low} minor wording issue${low === 1 ? '' : 's'} flagged.`;
  } else if (high > 0) {
    const topLabels = [...new Set(findings.filter((f) => f.severity === 'high').map((f) => f.concernLabel))].slice(0, 2);
    summary = `${high} high-severity issue${high === 1 ? '' : 's'} flagged${
      topLabels.length ? `, primarily around ${topLabels.join(' and ')}` : ''
    }${medium > 0 ? `, plus ${medium} medium-severity issue${medium === 1 ? '' : 's'}` : ''}.`;
  } else {
    summary = `${medium} medium-severity issue${medium === 1 ? '' : 's'} flagged — worth negotiating but not urgent.`;
  }

  return { score, grade, summary };
}
