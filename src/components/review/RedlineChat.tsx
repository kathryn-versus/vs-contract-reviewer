'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/Button';
import type { Finding, ThreadMessage } from '@/lib/types';

export function RedlineChat({
  issue,
  clientNotes,
  initialMessages,
  onPersist,
}: {
  issue: Finding;
  clientNotes?: string | null;
  initialMessages: ThreadMessage[];
  onPersist: (messages: ThreadMessage[]) => void;
}) {
  const [messages, setMessages] = useState<ThreadMessage[]>(initialMessages);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);

  async function send() {
    if (!input.trim()) return;
    const userMsg: ThreadMessage = { role: 'user', content: input.trim(), timestamp: Date.now() };
    const next = [...messages, userMsg];
    setMessages(next);
    setInput('');
    setLoading(true);
    try {
      const res = await fetch('/api/review/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ issue, clientNotes, messages: next }),
      });
      const data = await res.json();
      if (data.message) {
        const withReply = [...next, data.message as ThreadMessage];
        setMessages(withReply);
        onPersist(withReply);
      }
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="mt-4 rounded-sm border border-rule bg-paper">
      <div className="max-h-64 space-y-3 overflow-y-auto p-4">
        {messages.length === 0 && (
          <p className="font-mono text-xs text-ink-faint">
            Ask for a fallback position, a different framing, or push back on the initial recommendation.
          </p>
        )}
        {messages.map((m, i) => (
          <div key={i} className={m.role === 'user' ? 'text-right' : 'text-left'}>
            <span
              className={
                m.role === 'user'
                  ? 'inline-block max-w-[85%] rounded-sm bg-ink px-3 py-2 text-left text-sm text-paper'
                  : 'inline-block max-w-[85%] rounded-sm bg-accent-soft/20 px-3 py-2 text-left text-sm text-ink'
              }
            >
              {m.content}
            </span>
          </div>
        ))}
        {loading && <p className="font-mono text-xs text-ink-faint">Thinking…</p>}
      </div>
      <div className="flex gap-2 border-t border-rule p-3">
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && send()}
          placeholder="They won't accept mutual — give me a fallback"
          className="flex-1 border border-rule bg-paper px-3 py-1.5 font-body text-sm outline-none focus:border-ink"
        />
        <Button variant="primary" onClick={send} disabled={loading}>
          Send
        </Button>
      </div>
    </div>
  );
}
