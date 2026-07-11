#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_default_review_and_library_search.sh
set -e

# ── 1. Default the intake form to "File for reference (no review)" ─────────
python3 - << 'PYEOF'
path = "src/components/intake/IntakeForm.tsx"
with open(path) as f:
    content = f.read()

old = "  const [skipReview, setSkipReview] = useState(false);"
new = "  // Defaults to true — filing without review is now the default path;\n  // a reviewer has to actively click \"Run Claude review\" to opt into\n  // analysis, rather than the other way around.\n  const [skipReview, setSkipReview] = useState(true);"

if "Defaults to true" in content:
    print("IntakeForm.tsx: default already flipped — nothing to do.")
elif old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("IntakeForm.tsx: skipReview now defaults to true.")
else:
    raise SystemExit(
        "Expected skipReview state line not found in "
        "src/components/intake/IntakeForm.tsx — aborting. Paste me the "
        "current file and I'll fix it by hand."
    )
PYEOF

# ── 2. New shared helper: src/lib/recents.ts ────────────────────────────────
cat > "src/lib/recents.ts" << 'VS_APPLY_EOF_recents'
'use client';

// Tracks recently-viewed clients in localStorage — a lightweight convenience
// for the Library home page, not critical data, so every function here fails
// silently rather than throwing (e.g. if localStorage is unavailable, as in
// some private-browsing modes).

const RECENTS_KEY = 'vs_recent_clients';
const MAX_RECENTS = 8;

export function getRecentClientIds(): string[] {
  if (typeof window === 'undefined') return [];
  try {
    const raw = localStorage.getItem(RECENTS_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

export function recordRecentClient(clientId: string) {
  if (typeof window === 'undefined') return;
  try {
    const existing = getRecentClientIds().filter((id) => id !== clientId);
    const updated = [clientId, ...existing].slice(0, MAX_RECENTS);
    localStorage.setItem(RECENTS_KEY, JSON.stringify(updated));
  } catch {
    // Non-fatal.
  }
}
VS_APPLY_EOF_recents
echo "Wrote src/lib/recents.ts"

# ── 3. src/components/library/ClientListView.tsx — search + recents ────────
cat > "src/components/library/ClientListView.tsx" << 'VS_APPLY_EOF_clientlist'
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
VS_APPLY_EOF_clientlist
echo "Wrote src/components/library/ClientListView.tsx"

# ── 4. src/components/library/ClientDetailView.tsx — record recent + deep-link ──
python3 - << 'PYEOF'
path = "src/components/library/ClientDetailView.tsx"
with open(path) as f:
    content = f.read()

if "recordRecentClient" in content:
    print("ClientDetailView.tsx: already has recents/deep-link — nothing to do.")
else:
    old_import = "} from '@/lib/firebase/firestore';\nimport type { ClientDoc, ContractDoc } from '@/lib/types';"
    new_import = "} from '@/lib/firebase/firestore';\nimport { recordRecentClient } from '@/lib/recents';\nimport type { ClientDoc, ContractDoc } from '@/lib/types';"

    old_state = "  const [msaError, setMsaError] = useState<string | null>(null);"
    new_state = (
        "  const [msaError, setMsaError] = useState<string | null>(null);\n"
        "  // Set from a #matter-{id} URL hash (e.g. arriving from a Library search\n"
        "  // result) — auto-expands and scrolls to that specific matter.\n"
        "  const [autoExpandMatterId, setAutoExpandMatterId] = useState<string | null>(null);"
    )

    old_effect = """  useEffect(() => {
    getClient(clientId).then((c) => {
      setClient(c);
      setNotes(c?.notes ?? '');
    });
    listContractsForClient(clientId).then(setContracts);
    listClients().then(setAllClients);
  }, [clientId]);"""
    new_effect = """  useEffect(() => {
    getClient(clientId).then((c) => {
      setClient(c);
      setNotes(c?.notes ?? '');
    });
    listContractsForClient(clientId).then(setContracts);
    listClients().then(setAllClients);
    recordRecentClient(clientId);

    if (typeof window !== 'undefined' && window.location.hash.startsWith('#matter-')) {
      setAutoExpandMatterId(window.location.hash.replace('#matter-', ''));
    }
  }, [clientId]);

  // Scroll to the deep-linked matter once its contracts have loaded (can't
  // scroll to an element that hasn't rendered yet).
  useEffect(() => {
    if (!autoExpandMatterId || contracts.length === 0) return;
    document.getElementById(`matter-${autoExpandMatterId}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }, [autoExpandMatterId, contracts]);"""

    old_matters_render = """        {contracts.map((c) => (
          <MatterCard
            key={c.id}
            contract={c}
            onEdit={() => setEditing(c)}
            isGoverningMsa={client.msaContractId === c.id}
            onToggleGoverningMsa={() => handleToggleGoverningMsa(c.id)}
          />
        ))}"""
    new_matters_render = """        {contracts.map((c) => (
          <div key={c.id} id={`matter-${c.id}`}>
            <MatterCard
              contract={c}
              onEdit={() => setEditing(c)}
              isGoverningMsa={client.msaContractId === c.id}
              onToggleGoverningMsa={() => handleToggleGoverningMsa(c.id)}
              autoExpand={autoExpandMatterId === c.id}
            />
          </div>
        ))}"""

    missing = [
        label for label, needle in [
            ("import", old_import),
            ("state", old_state),
            ("effect", old_effect),
            ("matters render", old_matters_render),
        ] if needle not in content
    ]
    if missing:
        raise SystemExit(
            f"Expected block(s) not found in ClientDetailView.tsx: {missing} — "
            "aborting. Paste me the current file and I'll fix it by hand."
        )

    content = (
        content.replace(old_import, new_import)
        .replace(old_state, new_state)
        .replace(old_effect, new_effect)
        .replace(old_matters_render, new_matters_render)
    )
    with open(path, "w") as f:
        f.write(content)
    print("ClientDetailView.tsx: records recent client + supports #matter- deep link.")
PYEOF

# ── 5. src/components/library/MatterCard.tsx — accept autoExpand ───────────
python3 - << 'PYEOF'
path = "src/components/library/MatterCard.tsx"
with open(path) as f:
    content = f.read()

if "autoExpand" in content:
    print("MatterCard.tsx: already accepts autoExpand — nothing to do.")
else:
    old_sig = """export function MatterCard({
  contract,
  onEdit,
  isGoverningMsa,
  onToggleGoverningMsa,
}: {
  contract: ContractDoc;
  onEdit: () => void;
  isGoverningMsa?: boolean;
  onToggleGoverningMsa?: () => void;
}) {
  const [versions, setVersions] = useState<VersionDoc[]>([]);
  const [expanded, setExpanded] = useState(false);"""
    new_sig = """export function MatterCard({
  contract,
  onEdit,
  isGoverningMsa,
  onToggleGoverningMsa,
  autoExpand,
}: {
  contract: ContractDoc;
  onEdit: () => void;
  isGoverningMsa?: boolean;
  onToggleGoverningMsa?: () => void;
  /** Expands and highlights this card on mount — set when arriving via a
   * Library search result's #matter-{id} deep link. */
  autoExpand?: boolean;
}) {
  const [versions, setVersions] = useState<VersionDoc[]>([]);
  const [expanded, setExpanded] = useState(Boolean(autoExpand));

  useEffect(() => {
    if (autoExpand) setExpanded(true);
  }, [autoExpand]);"""

    old_card_open = '    <Card className="p-5">'
    new_card_open = "    <Card className={autoExpand ? 'p-5 ring-2 ring-accent' : 'p-5'}>"

    if old_sig not in content or old_card_open not in content:
        raise SystemExit(
            "Expected signature/Card block not found in "
            "src/components/library/MatterCard.tsx — aborting. Paste me the "
            "current file and I'll fix it by hand."
        )

    content = content.replace(old_sig, new_sig).replace(old_card_open, new_card_open, 1)
    with open(path, "w") as f:
        f.write(content)
    print("MatterCard.tsx: accepts autoExpand, highlights + expands when set.")
PYEOF

echo ""
echo "Done. Restart your dev server and test:"
echo "  1. New intake form should default to 'File for reference' — you have"
echo "     to click 'Run Claude review' to opt into analysis."
echo "  2. On the Library home, type a job number or counterparty into the"
echo "     search box — matching jobs should appear above the client grid,"
echo "     and clicking one should jump to that client's page with the"
echo "     matter highlighted and scrolled into view."
echo "  3. Visit a couple of different clients, then go back to the Library"
echo "     home — a 'Recently viewed' row should appear above the search"
echo "     results."
echo ""
echo "Then commit and push (via GitHub Desktop) to trigger a new rollout."
