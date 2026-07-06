'use client';

import { useEffect, useState } from 'react';

const MESSAGES = [
  'Scanning document structure…',
  'Cross-referencing the eight standing concerns…',
  'Checking termination and cure provisions…',
  'Evaluating indemnification and liability language…',
  'Reviewing AI and subcontractor clauses…',
  'Drafting severity assessments…',
];

export function LoadingScan() {
  const [i, setI] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setI((v) => (v + 1) % MESSAGES.length), 1800);
    return () => clearInterval(id);
  }, []);

  return (
    <div className="flex flex-col items-center justify-center gap-4 py-20 text-center">
      <div className="relative h-14 w-11 border-2 border-ink">
        <div className="absolute left-0 top-0 h-0.5 w-full animate-pulse bg-accent" />
        <div className="absolute inset-x-1.5 top-3 h-0.5 bg-rule" />
        <div className="absolute inset-x-1.5 top-6 h-0.5 bg-rule" />
        <div className="absolute inset-x-1.5 top-9 h-0.5 bg-rule" />
      </div>
      <p className="font-mono text-xs uppercase tracking-wide text-ink-faint transition-opacity">
        {MESSAGES[i]}
      </p>
    </div>
  );
}
