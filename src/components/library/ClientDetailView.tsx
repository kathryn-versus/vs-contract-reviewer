'use client';

import { useEffect, useState } from 'react';
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
} from '@/lib/firebase/firestore';
import type { ClientDoc, ContractDoc } from '@/lib/types';

export function ClientDetailView({ clientId }: { clientId: string }) {
  const [client, setClient] = useState<ClientDoc | null>(null);
  const [contracts, setContracts] = useState<ContractDoc[]>([]);
  const [allClients, setAllClients] = useState<ClientDoc[]>([]);
  const [notes, setNotes] = useState('');
  const [savingNotes, setSavingNotes] = useState(false);
  const [editing, setEditing] = useState<ContractDoc | null>(null);

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

  return (
    <div className="space-y-8">
      <div>
        <h1 className="font-display text-2xl text-ink">{client.name}</h1>
        <p className="font-mono text-xs text-ink-faint">{contracts.length} matters on file</p>
      </div>

      {msaContract && (
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

