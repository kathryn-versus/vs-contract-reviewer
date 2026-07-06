'use client';

import { useEffect, useState } from 'react';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { listClients } from '@/lib/firebase/firestore';
import type { ClientDoc } from '@/lib/types';

export function ClientLibraryManagement() {
  const [clients, setClients] = useState<ClientDoc[]>([]);
  const [a, setA] = useState('');
  const [b, setB] = useState('');

  useEffect(() => {
    listClients().then(setClients);
  }, []);

  return (
    <Card className="p-5">
      <p className="mb-4 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
        Client library management
      </p>
      <div className="flex flex-wrap items-end gap-3">
        <label className="block">
          <span className="mb-1 block font-mono text-xs text-ink-faint">Merge into</span>
          <select value={a} onChange={(e) => setA(e.target.value)} className="border border-rule px-3 py-2 text-sm">
            <option value="">Select client…</option>
            {clients.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        </label>
        <label className="block">
          <span className="mb-1 block font-mono text-xs text-ink-faint">Duplicate to merge & delete</span>
          <select value={b} onChange={(e) => setB(e.target.value)} className="border border-rule px-3 py-2 text-sm">
            <option value="">Select client…</option>
            {clients.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        </label>
        <Button variant="danger" disabled={!a || !b || a === b}>
          Merge & delete duplicate
        </Button>
      </div>
      <p className="mt-3 font-body text-xs text-ink-faint">
        Merging reassigns every contract from the duplicate to the target client, then deletes the
        duplicate client record. Implement via an admin-only Cloud Function for atomicity in production.
      </p>
    </Card>
  );
}
