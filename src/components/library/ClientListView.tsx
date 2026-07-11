'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { subscribeClients, getOrCreateClient, ensureClientDriveFolder } from '@/lib/firebase/firestore';
import { db } from '@/lib/firebase/client';
import { useAuth } from '@/hooks/useAuth';
import { getRecentClientIds } from '@/lib/recents';
import type { ClientDoc, ContractDoc } from '@/lib/types';

export function ClientListView() {
  const { user } = useAuth();
  const [clients, setClients] = useState<ClientDoc[]>([]);
  const [contractsByClient, setContractsByClient] = useState<Record<string, ContractDoc[]>>({});
  const [search, setSearch] = useState('');
  const [adding, setAdding] = useState(false);
  const [newName, setNewName] = useState('');
  const [creating, setCreating] = useState(false);
  const [recentClientIds, setRecentClientIds] = useState<string[]>([]);

  useEffect(() => subscribeClients(setClients), []);

  useEffect(() => {
    setRecentClientIds(getRecentClientIds());
  }, []);

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

  // Matches by job name/number or counterparty across EVERY client — lets a
  // job number or counterparty jump straight to the matter without needing
  // to know (and browse to) the client first.
  const matchingMatters = useMemo(() => {
    const term = search.trim().toLowerCase();
    if (!term) return [];
    const all = Object.values(contractsByClient).flat();
    return all
      .filter(
        (c) =>
          c.projectName.toLowerCase().includes(term) ||
          c.projectNumber.toLowerCase().includes(term) ||
          c.counterparty.toLowerCase().includes(term)
      )
      .slice(0, 20);
  }, [contractsByClient, search]);

  const recentClients = useMemo(
    () => recentClientIds.map((id) => clients.find((c) => c.id === id)).filter((c): c is ClientDoc => Boolean(c)),
    [recentClientIds, clients]
  );

  async function handleNewClient() {
    if (!newName.trim() || !user?.email) return;
    setCreating(true);
    try {
      const client = await getOrCreateClient(newName.trim(), user.email);
      // Create the client's Drive folder right away — the client page shows
      // a link to it as soon as this finishes (or a retry button if it
      // failed, e.g. a transient Drive API error).
      await ensureClientDriveFolder(client);
      setNewName('');
      setAdding(false);
    } finally {
      setCreating(false);
    }
  }

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="font-display text-2xl text-ink">Client Library</h1>
        <div className="flex items-center gap-2">
          <Link href="/batch-import">
            <Button variant="ghost">Batch import</Button>
          </Link>
          <Button variant="primary" onClick={() => setAdding((v) => !v)}>
            + New Client
          </Button>
        </div>
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
          <Button variant="primary" onClick={handleNewClient} disabled={creating}>
            {creating ? 'Creating…' : 'Create'}
          </Button>
        </Card>
      )}

      <input
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        placeholder="Search clients, jobs, job numbers, or counterparties…"
        className="mb-4 w-full border border-rule px-3 py-2 text-sm outline-none focus:border-ink"
      />

      {!search.trim() && recentClients.length > 0 && (
        <div className="mb-6">
          <p className="mb-2 font-mono text-[11px] uppercase tracking-wide text-ink-faint">Recently viewed</p>
          <div className="flex flex-wrap gap-2">
            {recentClients.map((c) => (
              <Link
                key={c.id}
                href={`/library/${c.id}`}
                className="rounded-full border border-rule px-3 py-1 font-mono text-xs text-ink-soft hover:border-ink hover:text-ink"
              >
                {c.name}
              </Link>
            ))}
          </div>
        </div>
      )}

      {search.trim() && matchingMatters.length > 0 && (
        <div className="mb-6">
          <p className="mb-2 font-mono text-[11px] uppercase tracking-wide text-ink-faint">Matching jobs</p>
          <div className="space-y-2">
            {matchingMatters.map((m) => (
              <Link
                key={m.id}
                href={`/library/${m.clientId}#matter-${m.id}`}
                className="block rounded-sm border border-rule bg-paper p-3 transition hover:border-ink"
              >
                <p className="font-body text-sm text-ink">
                  {m.projectName} <span className="font-mono text-xs text-ink-faint">({m.projectNumber})</span>
                </p>
                <p className="font-mono text-xs text-ink-faint">
                  {m.clientName} · {m.docType} · Counterparty: {m.counterparty}
                </p>
              </Link>
            ))}
          </div>
        </div>
      )}

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
                  {client.msaContractId || client.msaDriveFileId ? (
                    <span className="text-low">MSA on file</span>
                  ) : client.noMsa ? (
                    <span className="text-ink-faint">No MSA</span>
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
