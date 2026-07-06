'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { subscribeClients, getOrCreateClient } from '@/lib/firebase/firestore';
import { db } from '@/lib/firebase/client';
import { useAuth } from '@/hooks/useAuth';
import type { ClientDoc, ContractDoc } from '@/lib/types';

export function ClientListView() {
  const { user } = useAuth();
  const [clients, setClients] = useState<ClientDoc[]>([]);
  const [contractsByClient, setContractsByClient] = useState<Record<string, ContractDoc[]>>({});
  const [search, setSearch] = useState('');
  const [adding, setAdding] = useState(false);
  const [newName, setNewName] = useState('');

  useEffect(() => subscribeClients(setClients), []);

  // Fetch all contracts once and group client-side (small dataset expected).
  useEffect(() => {
    (async () => {
      const { collection, getDocs: gd } = await import('firebase/firestore');
      const snap = await gd(collection(db, 'contracts'));
      const grouped: Record<string, ContractDoc[]> = {};
      snap.docs.forEach((d) => {
        const data = d.data() as Omit<ContractDoc, 'id'>;
        const c: ContractDoc = { id: d.id, ...data, createdAt: Date.now() };
        grouped[c.clientId] = grouped[c.clientId] || [];
        grouped[c.clientId].push(c);
      });
      setContractsByClient(grouped);
    })().catch(() => {});
  }, []);

  const filtered = useMemo(
    () => clients.filter((c) => c.name.toLowerCase().includes(search.toLowerCase())),
    [clients, search]
  );

  async function handleNewClient() {
    if (!newName.trim() || !user?.email) return;
    await getOrCreateClient(newName.trim(), user.email);
    setNewName('');
    setAdding(false);
  }

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="font-display text-2xl text-ink">Client Library</h1>
        <Button variant="primary" onClick={() => setAdding((v) => !v)}>
          + New Client
        </Button>
      </div>

      {adding && (
        <Card className="mb-6 flex items-center gap-2 p-4">
          <input
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            placeholder="Client name"
            className="flex-1 border border-rule px-3 py-1.5 text-sm outline-none focus:border-ink"
            onKeyDown={(e) => e.key === 'Enter' && handleNewClient()}
          />
          <Button variant="primary" onClick={handleNewClient}>Create</Button>
        </Card>
      )}

      <input
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        placeholder="Search clients…"
        className="mb-4 w-full border border-rule px-3 py-2 text-sm outline-none focus:border-ink"
      />

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {filtered.map((client) => {
          const matters = contractsByClient[client.id] ?? [];
          const mostRecent = matters[0]?.createdAt;
          return (
            <Link key={client.id} href={`/library/${client.id}`}>
              <Card className="p-4 transition hover:border-ink">
                <p className="font-display text-lg text-ink">{client.name}</p>
                <p className="mt-1 font-mono text-xs text-ink-faint">
                  {matters.length} matter{matters.length === 1 ? '' : 's'}
                </p>
                <p className="mt-1 font-mono text-xs text-ink-faint">
                  {mostRecent ? `Last upload ${new Date(mostRecent).toLocaleDateString()}` : 'No uploads yet'}
                </p>
                <p className="mt-2 font-mono text-[11px] uppercase tracking-wide">
                  {client.msaContractId ? (
                    <span className="text-low">MSA on file</span>
                  ) : (
                    <span className="text-med">MSA missing</span>
                  )}
                </p>
              </Card>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
