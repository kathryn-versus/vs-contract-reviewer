'use client';

import { useState } from 'react';
import clsx from 'clsx';
import { SeverityBadge } from '@/components/ui/SeverityBadge';
import { RedlineChat } from './RedlineChat';
import type { Finding, ThreadMessage } from '@/lib/types';

const borderColor: Record<Finding['severity'], string> = {
  high: 'border-l-high',
  medium: 'border-l-med',
  low: 'border-l-low',
};

export function IssueCard({
  finding,
  selected,
  onToggleSelect,
  clientNotes,
  threadMessages,
  onPersistThread,
  redlineText,
}: {
  finding: Finding;
  selected: boolean;
  onToggleSelect: () => void;
  clientNotes?: string | null;
  threadMessages: ThreadMessage[];
  onPersistThread: (messages: ThreadMessage[]) => void;
  redlineText?: string | null;
}) {
  const [expanded, setExpanded] = useState(false);
  const [chatOpen, setChatOpen] = useState(false);

  return (
    <div className={clsx('rounded-sm border border-rule border-l-4 bg-paper', borderColor[finding.severity])}>
      <div className="flex items-start gap-3 p-4">
        <input
          type="checkbox"
          checked={selected}
          onChange={onToggleSelect}
          className="mt-1 h-4 w-4 accent-ink"
          aria-label="Select for redline"
        />
        <button className="flex-1 text-left" onClick={() => setExpanded((v) => !v)}>
          <div className="flex flex-wrap items-center gap-2">
            <SeverityBadge severity={finding.severity} />
            <span className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">
              {finding.concernLabel}
            </span>
          </div>
          <p className="mt-1.5 font-display text-base text-ink">{finding.issueTitle}</p>
          {finding.location && (
            <p className="mt-0.5 font-mono text-xs text-ink-faint">{finding.location}</p>
          )}
        </button>
        <span className="mt-1 font-mono text-xs text-ink-faint">{expanded ? '−' : '+'}</span>
      </div>

      {expanded && (
        <div className="space-y-4 border-t border-rule px-4 pb-4 pt-4">
          <div>
            <p className="mb-1 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
              Verbatim clause
            </p>
            <blockquote className="border-l-2 border-rule pl-3 font-body text-sm italic text-ink-soft">
              “{finding.quote}”
            </blockquote>
          </div>
          <div>
            <p className="mb-1 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
              Why it matters
            </p>
            <p className="font-body text-sm text-ink">{finding.analysis}</p>
          </div>
          <div>
            <p className="mb-1 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
              Negotiation direction
            </p>
            <p className="font-body text-sm text-ink">{finding.recommendation}</p>
          </div>

          {redlineText && (
            <div>
              <p className="mb-1 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
                Drafted redline
              </p>
              <p className="whitespace-pre-wrap rounded-sm bg-accent-soft/15 p-3 font-mono text-xs text-ink">
                {redlineText}
              </p>
            </div>
          )}

          <button
            onClick={() => setChatOpen((v) => !v)}
            className="font-mono text-xs uppercase tracking-wide text-accent hover:underline"
          >
            {chatOpen ? 'Hide redline chat' : 'Refine this redline →'}
          </button>

          {chatOpen && (
            <RedlineChat
              issue={finding}
              clientNotes={clientNotes}
              initialMessages={threadMessages}
              onPersist={onPersistThread}
            />
          )}
        </div>
      )}
    </div>
  );
}
