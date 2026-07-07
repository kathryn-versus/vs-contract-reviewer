'use client';

import { useEffect, useState } from 'react';

const MESSAGES = [
  'Scanning document structure…',
  'Cross-referencing the standing concerns…',
  'Checking termination and cure provisions…',
  'Evaluating indemnification and liability language…',
  'Reviewing AI and subcontractor clauses…',
  'Checking payment terms against standard structures…',
  'Drafting severity assessments…',
];

// A full analysis pass is one Claude call over the whole document text, so
// there's no real server-side progress to stream (yet) — this paces a
// progress bar against a typical-duration estimate instead, easing toward
// ~95% so it visibly moves the whole time but never falsely claims "done"
// before the response actually comes back and this view unmounts.
const ESTIMATED_MS = 35_000;

export function LoadingScan() {
  const [i, setI] = useState(0);
  const [elapsed, setElapsed] = useState(0);

  useEffect(() => {
    const messageId = setInterval(() => setI((v) => (v + 1) % MESSAGES.length), 1800);
    const start = Date.now();
    const tickId = setInterval(() => setElapsed(Date.now() - start), 200);
    return () => {
      clearInterval(messageId);
      clearInterval(tickId);
    };
  }, []);

  const percent = Math.min(95, Math.round(95 * (1 - Math.exp(-elapsed / ESTIMATED_MS))));

  return (
    <div className="flex flex-col items-center justify-center gap-4 py-20 text-center">
      <div className="relative h-14 w-11 border-2 border-ink">
        <div className="absolute left-0 top-0 h-0.5 w-full animate-pulse bg-accent" />
        <div className="absolute inset-x-1.5 top-3 h-0.5 bg-rule" />
        <div className="absolute inset-x-1.5 top-6 h-0.5 bg-rule" />
        <div className="absolute inset-x-1.5 top-9 h-0.5 bg-rule" />
      </div>

      <div className="w-64">
        <div className="h-1 w-full overflow-hidden rounded-full bg-rule">
          <div
            className="h-full bg-accent transition-[width] duration-300 ease-out"
            style={{ width: `${percent}%` }}
          />
        </div>
        <p className="mt-1.5 font-mono text-[11px] text-ink-faint">{percent}%</p>
      </div>

      <p className="font-mono text-xs uppercase tracking-wide text-ink-faint transition-opacity">
        {MESSAGES[i]}
      </p>
    </div>
  );
}
