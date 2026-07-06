'use client';

import { useEffect, useState } from 'react';
import { Drawer } from '@/components/ui/Drawer';
import type { Finding } from '@/lib/types';

interface PriorityResult {
  priorityOrder: { uid: string; rank: number; rationale: string }[];
  strategyNotes: string;
}

export function PrioritizeDrawer({
  open,
  onClose,
  findings,
}: {
  open: boolean;
  onClose: () => void;
  findings: Finding[];
}) {
  const [result, setResult] = useState<PriorityResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setLoading(true);
    setError(null);
    fetch('/api/review/prioritize', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ findings }),
    })
      .then((r) => r.json())
      .then((data) => {
        if (data.error) setError(data.error);
        else setResult(data);
      })
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const byUid = new Map(findings.map((f) => [f.uid, f]));

  return (
    <Drawer open={open} onClose={onClose} title="Prioritize for negotiation">
      {loading && <p className="font-mono text-sm text-ink-faint">Building negotiation strategy…</p>}
      {error && <p className="text-sm text-high">{error}</p>}
      {result && (
        <div className="space-y-6">
          <p className="font-body text-sm text-ink-soft">{result.strategyNotes}</p>
          <ol className="space-y-3">
            {result.priorityOrder
              .sort((a, b) => a.rank - b.rank)
              .map((p) => {
                const f = byUid.get(p.uid);
                return (
                  <li key={p.uid} className="border-l-2 border-ink pl-3">
                    <p className="font-mono text-xs text-ink-faint">#{p.rank}</p>
                    <p className="font-display text-sm text-ink">{f?.issueTitle ?? p.uid}</p>
                    <p className="mt-1 font-body text-sm text-ink-soft">{p.rationale}</p>
                  </li>
                );
              })}
          </ol>
        </div>
      )}
    </Drawer>
  );
}
