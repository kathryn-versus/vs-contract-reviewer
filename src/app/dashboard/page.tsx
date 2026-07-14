'use client';

import { useEffect, useState } from 'react';
import clsx from 'clsx';
import { AuthGuard } from '@/components/layout/AuthGuard';
import { AppShell } from '@/components/layout/AppShell';
import { Card } from '@/components/ui/Card';
import { listAllContracts, getVersion } from '@/lib/firebase/firestore';
import { computeReviewScore } from '@/lib/report/scoring';
import { CONCERN_SHORT_LABELS } from '@/lib/types';
import type { ContractDoc, VersionDoc } from '@/lib/types';

// Admin-only portfolio view — trends across every matter on file, not just
// one client at a time like the Library. Pulls each contract's LATEST
// version only (not every version in its history), so stats reflect current
// state rather than double-counting superseded drafts.
export default function DashboardPage() {
  return (
    <AuthGuard requireRole="admin">
      <AppShell>
        <DashboardView />
      </AppShell>
    </AuthGuard>
  );
}

interface Snapshot {
  contract: ContractDoc;
  version: VersionDoc;
}

const GRADE_ORDER = ['A', 'B', 'C', 'D', 'F'] as const;
const GRADE_COLOR: Record<string, string> = {
  A: 'bg-low',
  B: 'bg-low',
  C: 'bg-med',
  D: 'bg-high',
  F: 'bg-high',
};

function DashboardView() {
  const [snapshots, setSnapshots] = useState<Snapshot[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const contracts = await listAllContracts();
      const results = await Promise.all(
        contracts
          .filter((c) => c.latestVersionId)
          .map(async (c) => {
            const v = await getVersion(c.id, c.latestVersionId!);
            return v ? { contract: c, version: v } : null;
          })
      );
      if (!cancelled) {
        setSnapshots(results.filter((r): r is Snapshot => r !== null));
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  if (!snapshots) {
    return <p className="font-mono text-sm text-ink-faint">Loading…</p>;
  }

  const reviewed = snapshots.filter((s) => s.version.reviewed !== false);
  const filedOnly = snapshots.length - reviewed.length;

  const grades: Record<string, number> = { A: 0, B: 0, C: 0, D: 0, F: 0 };
  const concernCounts = new Map<string, number>();
  let scoreSum = 0;

  for (const { version } of reviewed) {
    const { score, grade } = computeReviewScore(version.findings);
    grades[grade] = (grades[grade] ?? 0) + 1;
    scoreSum += score;
    for (const f of version.findings) {
      const label = CONCERN_SHORT_LABELS[f.concernId] ?? f.concernLabel;
      concernCounts.set(label, (concernCounts.get(label) ?? 0) + 1);
    }
  }

  const monthCounts = new Map<string, number>();
  for (const { version } of snapshots) {
    const d = new Date(version.uploadedAt);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    monthCounts.set(key, (monthCounts.get(key) ?? 0) + 1);
  }

  const topConcerns = [...concernCounts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8);
  const months = [...monthCounts.entries()].sort((a, b) => a[0].localeCompare(b[0])).slice(-12);
  const maxMonthCount = Math.max(1, ...months.map(([, n]) => n));
  const maxConcernCount = Math.max(1, ...topConcerns.map(([, n]) => n));
  const totalGraded = reviewed.length || 1;
  const avgScore = reviewed.length ? Math.round(scoreSum / reviewed.length) : null;

  return (
    <div className="space-y-8">
      <h1 className="font-display text-2xl text-ink">Dashboard</h1>

      <div className="grid grid-cols-4 gap-3">
        <Card className="p-4 text-center">
          <p className="font-display text-2xl text-ink">{snapshots.length}</p>
          <p className="mt-1 font-mono text-[11px] uppercase tracking-wide text-ink-faint">Total matters</p>
        </Card>
        <Card className="p-4 text-center">
          <p className="font-display text-2xl text-ink">{reviewed.length}</p>
          <p className="mt-1 font-mono text-[11px] uppercase tracking-wide text-ink-faint">Reviewed by Claude</p>
        </Card>
        <Card className="p-4 text-center">
          <p className="font-display text-2xl text-ink">{filedOnly}</p>
          <p className="mt-1 font-mono text-[11px] uppercase tracking-wide text-ink-faint">Filed, not reviewed</p>
        </Card>
        <Card className="p-4 text-center">
          <p className="font-display text-2xl text-ink">{avgScore ?? '—'}</p>
          <p className="mt-1 font-mono text-[11px] uppercase tracking-wide text-ink-faint">Avg review score</p>
        </Card>
      </div>

      <Card className="p-5">
        <p className="mb-4 font-mono text-[11px] uppercase tracking-wide text-ink-faint">Grade distribution</p>
        {reviewed.length === 0 ? (
          <p className="font-mono text-sm text-ink-faint">No reviewed matters yet.</p>
        ) : (
          <div className="space-y-2">
            {GRADE_ORDER.map((g) => (
              <div key={g} className="flex items-center gap-3">
                <span className="w-4 font-display text-sm text-ink">{g}</span>
                <div className="h-3 flex-1 bg-rule/30">
                  <div
                    className={clsx('h-3', GRADE_COLOR[g])}
                    style={{ width: `${(grades[g] / totalGraded) * 100}%` }}
                  />
                </div>
                <span className="w-8 text-right font-mono text-xs text-ink-faint">{grades[g]}</span>
              </div>
            ))}
          </div>
        )}
      </Card>

      <Card className="p-5">
        <p className="mb-4 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
          Most frequently flagged concerns
        </p>
        {topConcerns.length === 0 ? (
          <p className="font-mono text-sm text-ink-faint">No findings yet.</p>
        ) : (
          <div className="space-y-2">
            {topConcerns.map(([label, count]) => (
              <div key={label} className="flex items-center gap-3">
                <span className="w-40 shrink-0 truncate font-body text-sm text-ink">{label}</span>
                <div className="h-3 flex-1 bg-rule/30">
                  <div className="h-3 bg-accent" style={{ width: `${(count / maxConcernCount) * 100}%` }} />
                </div>
                <span className="w-8 text-right font-mono text-xs text-ink-faint">{count}</span>
              </div>
            ))}
          </div>
        )}
      </Card>

      <Card className="p-5">
        <p className="mb-4 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
          Review volume (last 12 months)
        </p>
        {months.length === 0 ? (
          <p className="font-mono text-sm text-ink-faint">No data yet.</p>
        ) : (
          <div className="flex items-end gap-2" style={{ height: 120 }}>
            {months.map(([key, count]) => (
              <div key={key} className="flex flex-1 flex-col items-center gap-1">
                <div
                  className="w-full bg-accent"
                  style={{ height: `${Math.max(4, (count / maxMonthCount) * 100)}px` }}
                />
                <span className="font-mono text-[9px] text-ink-faint">{key.slice(5)}</span>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}
