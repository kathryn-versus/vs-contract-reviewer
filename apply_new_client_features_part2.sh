#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo, AFTER
# apply_new_client_features_part1.sh:
#   bash apply_new_client_features_part2.sh
#
# Part 2 of 2: UI — new client Drive-folder link, upload-contract button and
# MSA upload / No-MSA controls on the client page, and pre-filling the client
# name when jumping to upload from there.
set -e

# ── 1. src/components/library/ClientListView.tsx — create Drive folder on add ──
cat > "src/components/library/ClientListView.tsx" << 'VS_APPLY_EOF_clientlist'
'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { subscribeClients, getOrCreateClient, ensureClientDriveFolder } from '@/lib/firebase/firestore';
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
  const [creating, setCreating] = useState(false);

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

# ── 2. src/components/library/ClientDetailView.tsx — Drive link, upload,
#      and MSA controls ──────────────────────────────────────────────────────
cat > "src/components/library/ClientDetailView.tsx" << 'VS_APPLY_EOF_clientdetail'
'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { MatterCard } from './MatterCard';
import {
  getClient,
  listContractsForClient,
  updateClientNotes,
  moveContract,
  listClients,
  setGoverningMsa,
  clearGoverningMsa,
  ensureClientDriveFolder,
  setClientMsaFile,
  clearClientMsaFile,
  setClientNoMsa,
} from '@/lib/firebase/firestore';
import type { ClientDoc, ContractDoc } from '@/lib/types';

export function ClientDetailView({ clientId }: { clientId: string }) {
  const [client, setClient] = useState<ClientDoc | null>(null);
  const [contracts, setContracts] = useState<ContractDoc[]>([]);
  const [allClients, setAllClients] = useState<ClientDoc[]>([]);
  const [notes, setNotes] = useState('');
  const [savingNotes, setSavingNotes] = useState(false);
  const [editing, setEditing] = useState<ContractDoc | null>(null);
  const [creatingFolder, setCreatingFolder] = useState(false);
  const [uploadingMsa, setUploadingMsa] = useState(false);
  const [msaError, setMsaError] = useState<string | null>(null);

  useEffect(() => {
    getClient(clientId).then((c) => {
      setClient(c);
      setNotes(c?.notes ?? '');
    });
    listContractsForClient(clientId).then(setContracts);
    listClients().then(setAllClients);
  }, [clientId]);

  if (!client) {
    return <p className="font-mono text-sm text-ink-faint">Loading client…</p>;
  }

  const msaContract = contracts.find((c) => c.id === client.msaContractId);

  async function saveNotes() {
    setSavingNotes(true);
    try {
      await updateClientNotes(clientId, notes);
    } finally {
      setSavingNotes(false);
    }
  }

  async function handleReassign(contractId: string, newClientId: string, newProjectName: string) {
    const target = allClients.find((c) => c.id === newClientId);
    if (!target) return;
    await moveContract(contractId, { clientId: target.id, clientName: target.name, projectName: newProjectName });
    setEditing(null);
    listContractsForClient(clientId).then(setContracts);
  }

  async function handleToggleGoverningMsa(contractId: string) {
    if (!client) return;
    if (client.msaContractId === contractId) {
      await clearGoverningMsa(clientId);
    } else {
      await setGoverningMsa(clientId, contractId);
    }
    getClient(clientId).then(setClient);
  }

  async function handleEnsureFolder() {
    if (!client) return;
    setCreatingFolder(true);
    try {
      const updated = await ensureClientDriveFolder(client);
      setClient(updated);
    } finally {
      setCreatingFolder(false);
    }
  }

  async function handleMsaFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file || !client) return;
    setUploadingMsa(true);
    setMsaError(null);
    try {
      const form = new FormData();
      form.append('file', file);
      form.append('clientName', client.name);
      const res = await fetch('/api/drive/upload-msa', { method: 'POST', body: form });
      const data = await res.json();
      if (data.error) throw new Error(data.error);
      await setClientMsaFile(clientId, { msaDriveFileId: data.msaDriveFileId, msaDriveUrl: data.msaDriveUrl });
      getClient(clientId).then(setClient);
    } catch (err) {
      setMsaError(err instanceof Error ? err.message : 'MSA upload failed.');
    } finally {
      setUploadingMsa(false);
    }
  }

  async function handleClearMsaFile() {
    if (!client) return;
    await clearClientMsaFile(clientId);
    getClient(clientId).then(setClient);
  }

  async function handleSetNoMsa(value: boolean) {
    if (!client) return;
    await setClientNoMsa(clientId, value);
    getClient(clientId).then(setClient);
  }

  return (
    <div className="space-y-8">
      <div>
        <div className="flex flex-wrap items-center gap-3">
          <h1 className="font-display text-2xl text-ink">{client.name}</h1>
          {client.driveFolderUrl ? (
            <a
              href={client.driveFolderUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="font-mono text-xs text-accent hover:underline"
            >
              Drive folder ↗
            </a>
          ) : (
            <button
              type="button"
              onClick={handleEnsureFolder}
              disabled={creatingFolder}
              className="font-mono text-xs text-ink-faint hover:text-ink disabled:opacity-50"
            >
              {creatingFolder ? 'Creating…' : '+ Create Drive folder'}
            </button>
          )}
          <Link
            href={`/?clientName=${encodeURIComponent(client.name)}`}
            className="font-mono text-xs text-accent hover:underline"
          >
            + Upload contract
          </Link>
        </div>
        <p className="font-mono text-xs text-ink-faint">{contracts.length} matters on file</p>
      </div>

      {msaContract ? (
        <Card className="border-l-4 border-l-accent p-5">
          <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">Governing MSA</p>
          <p className="mt-1 font-display text-base text-ink">
            {msaContract.projectName} ({msaContract.projectNumber})
          </p>
          <p className="mt-2 font-body text-sm text-ink-soft">
            Its text is automatically pulled from Drive and given to Claude as context on every
            future SOW review for {client.name} — no manual setup needed per review.
          </p>
        </Card>
      ) : client.noMsa ? (
        <Card className="p-5">
          <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">Governing MSA</p>
          <p className="mt-1 font-body text-sm text-ink-soft">Marked as no MSA on file for {client.name}.</p>
          <button
            type="button"
            onClick={() => handleSetNoMsa(false)}
            className="mt-2 font-mono text-xs text-ink-faint hover:text-ink"
          >
            Undo
          </button>
        </Card>
      ) : client.msaDriveFileId ? (
        <Card className="p-5">
          <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">Governing MSA</p>
          <a
            href={client.msaDriveUrl ?? '#'}
            target="_blank"
            rel="noopener noreferrer"
            className="mt-1 block font-body text-sm text-accent hover:underline"
          >
            View MSA in Drive ↗
          </a>
          <p className="mt-2 font-body text-sm text-ink-soft">
            Its text is automatically pulled from Drive and given to Claude as context on every
            future SOW review for {client.name}.
          </p>
          <button
            type="button"
            onClick={handleClearMsaFile}
            className="mt-2 font-mono text-xs text-ink-faint hover:text-ink"
          >
            Remove
          </button>
        </Card>
      ) : (
        <Card className="p-5">
          <p className="mb-2 font-mono text-[11px] uppercase tracking-wide text-ink-faint">Governing MSA</p>
          <div className="flex flex-wrap items-center gap-4">
            <label className="cursor-pointer rounded-sm border border-rule px-3 py-1.5 font-mono text-xs uppercase tracking-wide text-ink-soft hover:border-ink">
              {uploadingMsa ? 'Uploading…' : 'Upload MSA'}
              <input
                type="file"
                accept=".pdf,.docx,.txt"
                className="hidden"
                onChange={handleMsaFile}
                disabled={uploadingMsa}
              />
            </label>
            <label className="flex items-center gap-1.5 font-mono text-xs text-ink-faint">
              <input
                type="checkbox"
                checked={client.noMsa}
                onChange={(e) => handleSetNoMsa(e.target.checked)}
              />
              No MSA for this client
            </label>
          </div>
          {msaError && <p className="mt-2 text-sm text-high">{msaError}</p>}
        </Card>
      )}

      <Card className="p-5">
        <p className="mb-2 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
          Client notes — fed to Claude as context on future reviews
        </p>
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          rows={3}
          placeholder='e.g. "Disney: AI clause non-negotiable per WDA amendment, do not flag as high"'
          className="w-full border border-rule bg-paper p-3 font-body text-sm outline-none focus:border-ink"
        />
        <div className="mt-2 flex justify-end">
          <Button variant="primary" onClick={saveNotes} disabled={savingNotes}>
            {savingNotes ? 'Saving…' : 'Save notes'}
          </Button>
        </div>
      </Card>

      <div className="space-y-3">
        <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">Matters</p>
        {contracts.map((c) => (
          <MatterCard
            key={c.id}
            contract={c}
            onEdit={() => setEditing(c)}
            isGoverningMsa={client.msaContractId === c.id}
            onToggleGoverningMsa={() => handleToggleGoverningMsa(c.id)}
          />
        ))}
        {contracts.length === 0 && (
          <p className="py-8 text-center font-mono text-sm text-ink-faint">No matters yet.</p>
        )}
      </div>

      {editing && (
        <EditMatterModal
          contract={editing}
          clients={allClients}
          onClose={() => setEditing(null)}
          onSave={handleReassign}
        />
      )}
    </div>
  );
}

function EditMatterModal({
  contract,
  clients,
  onClose,
  onSave,
}: {
  contract: ContractDoc;
  clients: ClientDoc[];
  onClose: () => void;
  onSave: (contractId: string, newClientId: string, newProjectName: string) => void;
}) {
  const [clientId, setClientId] = useState(contract.clientId);
  const [projectName, setProjectName] = useState(contract.projectName);

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-ink/30 p-6">
      <Card className="w-full max-w-md p-6">
        <h3 className="font-display text-lg text-ink">Edit matter</h3>
        <div className="mt-4 space-y-4">
          <label className="block">
            <span className="mb-1 block font-mono text-xs uppercase text-ink-faint">Client</span>
            <select
              value={clientId}
              onChange={(e) => setClientId(e.target.value)}
              className="w-full border border-rule px-3 py-2 text-sm"
            >
              {clients.map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </select>
          </label>
          <label className="block">
            <span className="mb-1 block font-mono text-xs uppercase text-ink-faint">Project name</span>
            <input
              value={projectName}
              onChange={(e) => setProjectName(e.target.value)}
              className="w-full border border-rule px-3 py-2 text-sm"
            />
          </label>
        </div>
        <div className="mt-6 flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button variant="primary" onClick={() => onSave(contract.id, clientId, projectName)}>
            Save & move Drive folder
          </Button>
        </div>
      </Card>
    </div>
  );
}
VS_APPLY_EOF_clientdetail
echo "Wrote src/components/library/ClientDetailView.tsx"

# ── 3. src/components/intake/IntakeForm.tsx — accept initialClientName ──────
python3 - << 'PYEOF'
path = "src/components/intake/IntakeForm.tsx"
with open(path) as f:
    content = f.read()

if "initialClientName" in content:
    print("IntakeForm.tsx: already has initialClientName — nothing to do.")
else:
    old_sig = """export function IntakeForm({
  user,
  onSubmit,
  submitting,
}: {
  user: User;
  onSubmit: (values: IntakeValues) => void;
  submitting: boolean;
}) {"""
    new_sig = """export function IntakeForm({
  user,
  onSubmit,
  submitting,
  initialClientName,
}: {
  user: User;
  onSubmit: (values: IntakeValues) => void;
  submitting: boolean;
  /** Pre-fills the Client field — used when jumping here from a client's own
   * page via "+ Upload contract", so the client doesn't need to be
   * re-selected. */
  initialClientName?: string;
}) {"""

    old_state = "  const [clientName, setClientName] = useState('');"
    new_state = "  const [clientName, setClientName] = useState(initialClientName ?? '');"

    if old_sig not in content or old_state not in content:
        raise SystemExit(
            "Expected signature/state not found in "
            "src/components/intake/IntakeForm.tsx — aborting. Paste me the "
            "current file and I'll fix it by hand."
        )

    content = content.replace(old_sig, new_sig).replace(old_state, new_state)
    with open(path, "w") as f:
        f.write(content)
    print("IntakeForm.tsx: added initialClientName prop.")
PYEOF

# ── 4. src/app/page.tsx — read ?clientName= and pass it through ─────────────
python3 - << 'PYEOF'
path = "src/app/page.tsx"
with open(path) as f:
    content = f.read()

if "useSearchParams" in content:
    print("page.tsx: already reads useSearchParams — nothing to do.")
else:
    old_imports = """'use client';

import { useState } from 'react';
import { AuthGuard } from '@/components/layout/AuthGuard';"""
    new_imports = """'use client';

import { Suspense, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import { AuthGuard } from '@/components/layout/AuthGuard';"""

    old_default_export = """export default function ReviewerPage() {
  return (
    <AuthGuard>
      <AppShell>
        <ReviewerFlow />
      </AppShell>
    </AuthGuard>
  );
}"""
    new_default_export = """export default function ReviewerPage() {
  return (
    <AuthGuard>
      <AppShell>
        {/* useSearchParams() (used below to pre-fill the client name when
            arriving via a client page's "+ Upload contract" link) requires a
            Suspense boundary for static generation to succeed in production —
            same fix as /login. */}
        <Suspense fallback={null}>
          <ReviewerFlow />
        </Suspense>
      </AppShell>
    </AuthGuard>
  );
}"""

    old_flow_start = """function ReviewerFlow() {
  const { user } = useAuth();
  const [step, setStep] = useState<Step>('intake');"""
    new_flow_start = """function ReviewerFlow() {
  const { user } = useAuth();
  const searchParams = useSearchParams();
  const initialClientName = searchParams.get('clientName') ?? undefined;
  const [step, setStep] = useState<Step>('intake');"""

    old_intake_render = '    return <IntakeForm user={user} onSubmit={handleSubmit} submitting={false} />;'
    new_intake_render = '    return <IntakeForm user={user} onSubmit={handleSubmit} submitting={false} initialClientName={initialClientName} />;'

    missing = [
        label for label, needle in [
            ("imports", old_imports),
            ("default export", old_default_export),
            ("ReviewerFlow start", old_flow_start),
            ("IntakeForm render", old_intake_render),
        ] if needle not in content
    ]
    if missing:
        raise SystemExit(
            f"Expected block(s) not found in src/app/page.tsx: {missing} — "
            "aborting. Paste me the current file and I'll fix it by hand."
        )

    content = (
        content.replace(old_imports, new_imports)
        .replace(old_default_export, new_default_export)
        .replace(old_flow_start, new_flow_start)
        .replace(old_intake_render, new_intake_render)
    )
    with open(path, "w") as f:
        f.write(content)
    print("page.tsx: reads ?clientName= and pre-fills the intake form.")
PYEOF

echo ""
echo "Both parts done. Restart your dev server and test:"
echo "  1. Add a new client from the Library — a Drive folder link should"
echo "     appear on their page (or a 'Create Drive folder' button if it"
echo "     failed, which you can click to retry)."
echo "  2. Click '+ Upload contract' on a client page — it should jump to the"
echo "     upload form with that client already filled in."
echo "  3. On a client with no matters reviewed yet, try 'Upload MSA' and the"
echo "     'No MSA for this client' checkbox."
echo ""
echo "Then commit and push (via GitHub Desktop) to trigger a new rollout."
