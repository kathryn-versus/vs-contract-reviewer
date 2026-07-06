'use client';

import { useEffect, useState } from 'react';
import { Drawer } from '@/components/ui/Drawer';
import type { Finding } from '@/lib/types';

interface RedlineResult {
  uid: string;
  redlineText: string;
  explanation: string;
}

export function RedlineDrawer({
  open,
  onClose,
  findings,
  onDrafted,
}: {
  open: boolean;
  onClose: () => void;
  findings: Finding[];
  onDrafted: (redlines: RedlineResult[]) => void;
}) {
  const [results, setResults] = useState<RedlineResult[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    setLoading(true);
    setError(null);
    fetch('/api/review/redline', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ issues: findings }),
    })
      .then((r) => r.json())
      .then((data) => {
        if (data.error) setError(data.error);
        else {
          setResults(data.redlines);
          onDrafted(data.redlines);
        }
      })
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const byUid = new Map(findings.map((f) => [f.uid, f]));

  return (
    <Drawer open={open} onClose={onClose} title="Draft redlines">
      {loading && <p className="font-mono text-sm text-ink-faint">Drafting redline language…</p>}
      {error && <p className="text-sm text-high">{error}</p>}
      {results && (
        <div className="space-y-6">
          {results.map((r) => (
            <div key={r.uid} className="border-b border-rule pb-4">
              <p className="font-display text-sm text-ink">{byUid.get(r.uid)?.issueTitle ?? r.uid}</p>
              <p className="mt-2 whitespace-pre-wrap rounded-sm bg-accent-soft/15 p-3 font-mono text-xs text-ink">
                {r.redlineText}
              </p>
              <p className="mt-2 font-body text-sm text-ink-soft">{r.explanation}</p>
            </div>
          ))}
        </div>
      )}
    </Drawer>
  );
}
