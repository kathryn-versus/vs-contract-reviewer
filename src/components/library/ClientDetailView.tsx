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
import { recordRecentClient } from '@/lib/recents';
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
  // Set from a #matter-{id} URL hash (e.g. arriving from a Library search
  // result) — auto-expands and scrolls to that specific matter.
  const [autoExpandMatterId, setAutoExpandMatterId] = useState<string | null>(null);

  useEffect(() => {
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
  }, [autoExpandMatterId, contracts]);

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
          <div key={c.id} id={`matter-${c.id}`}>
            <MatterCard
              contract={c}
              onEdit={() => setEditing(c)}
              isGoverningMsa={client.msaContractId === c.id}
              onToggleGoverningMsa={() => handleToggleGoverningMsa(c.id)}
              autoExpand={autoExpandMatterId === c.id}
            />
          </div>
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
