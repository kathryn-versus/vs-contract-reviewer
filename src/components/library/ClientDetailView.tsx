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
  listExecutedAgreements,
  addExecutedAgreement,
  deleteExecutedAgreement,
  createContract,
  addVersion,
  setContractMarkedReceived,
} from '@/lib/firebase/firestore';
import { recordRecentClient } from '@/lib/recents';
import { useAuth } from '@/hooks/useAuth';
import type { ClientDoc, ContractDoc, DocType, ExecutedAgreementDoc } from '@/lib/types';

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
  const [executedAgreements, setExecutedAgreements] = useState<ExecutedAgreementDoc[]>([]);
  const [agreementDocType, setAgreementDocType] = useState<DocType>('SOW');
  const [agreementLabel, setAgreementLabel] = useState('');
  const [agreementProjectKey, setAgreementProjectKey] = useState('');
  const [agreementNewProjectNumber, setAgreementNewProjectNumber] = useState('');
  const [agreementNewProjectName, setAgreementNewProjectName] = useState('');
  const [uploadingAgreement, setUploadingAgreement] = useState(false);
  const [agreementError, setAgreementError] = useState<string | null>(null);
  const { user } = useAuth();

  // Auto-suggest the next Change Order number so multiple change orders for
  // the same client don't collide or skip numbers — still editable/
  // overridable before upload, and only fires when switching TO Change
  // Order with an empty label (never overwrites something already typed).
  // Clears the suggestion back out if you switch to a different type
  // without having edited it, so a stale "Change Order #3" doesn't linger
  // on an MSA upload.
  useEffect(() => {
    if (agreementDocType === 'Change Order') {
      if (agreementLabel.trim() !== '') return;
      const count = executedAgreements.filter((a) => a.docType === 'Change Order').length;
      setAgreementLabel(`Change Order #${count + 1}`);
    } else if (/^Change Order #\d+$/.test(agreementLabel)) {
      setAgreementLabel('');
    }
  }, [agreementDocType, executedAgreements]);
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
    listExecutedAgreements(clientId).then(setExecutedAgreements);
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

  // SOWs and Change Orders are always tied to a specific job — MSA and
  // Other stay optional at the client level, since an MSA typically governs
  // many jobs rather than one.
  const REQUIRES_PROJECT: DocType[] = ['SOW', 'Change Order'];
  const projectOptionKey = (num: string, name: string) => `${num}—${name}`;
  const projectOptions = Array.from(
    new Map(
      contracts.map((c) => [
        projectOptionKey(c.projectNumber, c.projectName),
        { projectNumber: c.projectNumber, projectName: c.projectName },
      ])
    ).values()
  );
  function resolveAgreementProject(): { projectNumber: string; projectName: string } | null {
    if (agreementProjectKey === '__new__') {
      const projectNumber = agreementNewProjectNumber.trim();
      const projectName = agreementNewProjectName.trim();
      if (!projectNumber || !projectName) return null;
      return { projectNumber, projectName };
    }
    return projectOptions.find((p) => projectOptionKey(p.projectNumber, p.projectName) === agreementProjectKey) ?? null;
  }

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

  async function handleToggleMarkedReceived(contractId: string, value: boolean) {
    await setContractMarkedReceived(contractId, value);
    listContractsForClient(clientId).then(setContracts);
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

  async function handleUploadAgreement(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file || !client) return;
    const project = resolveAgreementProject();
    if (REQUIRES_PROJECT.includes(agreementDocType) && !project) {
      setAgreementError('Pick a project for this document type — SOWs and Change Orders are filed under a specific job.');
      return;
    }
    setUploadingAgreement(true);
    setAgreementError(null);
    try {
      // Resolve which matter this belongs to — matched by project number +
      // name against this client's existing matters — so the executed file
      // is connected to Matters/the matter count instead of floating as a
      // disconnected record.
      const existingMatter = project
        ? contracts.find(
            (c) => c.projectNumber === project.projectNumber && c.projectName === project.projectName
          )
        : null;
      let contractId: string | null = existingMatter?.id ?? null;

      const form = new FormData();
      form.append('file', file);
      form.append('clientName', client.name);
      form.append('docType', agreementDocType);
      form.append('label', agreementLabel);
      if (project) {
        form.append('projectNumber', project.projectNumber);
        form.append('projectName', project.projectName);
      }
      const res = await fetch('/api/drive/upload-executed-agreement', { method: 'POST', body: form });
      const data = await res.json();
      if (data.error) throw new Error(data.error);

      // A brand-new project typed in above has no matter yet — create one
      // now (plus a first, unreviewed version pointing at this same file)
      // so it shows up under Matters and counts correctly, instead of only
      // existing as an executed-agreement record with nowhere to attach.
      if (project && !contractId) {
        contractId = await createContract({
          clientId,
          clientName: client.name,
          projectName: project.projectName,
          projectNumber: project.projectNumber,
          docType: agreementDocType,
          counterparty: client.name,
          submittedBy: {
            uid: user?.uid ?? '',
            name: user?.displayName ?? user?.email ?? '',
            email: user?.email ?? '',
          },
          driveFileId: data.driveFileId ?? null,
          driveUrl: data.driveUrl ?? null,
          driveFolderUrl: data.driveFolderUrl ?? null,
          driveFolderId: null,
        });
        await addVersion(contractId, {
          versionNumber: 1,
          uploadedBy: { name: user?.displayName ?? user?.email ?? '', email: user?.email ?? '' },
          fileName: file.name,
          characterCount: 0,
          findings: [],
          insuranceRequirements: [],
          resolvedFindings: [],
          deltaFromPrevious: null,
          reviewed: false,
          driveFileId: data.driveFileId ?? null,
          driveUrl: data.driveUrl ?? null,
          driveFolderId: null,
          driveFolderUrl: data.driveFolderUrl ?? null,
          googleDocId: null,
          googleDocUrl: null,
          reportHtmlUrl: null,
          reportPdfUrl: null,
        });
        listContractsForClient(clientId).then(setContracts);
      }

      await addExecutedAgreement(clientId, {
        docType: agreementDocType,
        label: agreementLabel.trim(),
        driveFileId: data.driveFileId,
        driveUrl: data.driveUrl,
        driveFolderUrl: data.driveFolderUrl ?? null,
        contractId,
        projectNumber: project?.projectNumber ?? null,
        projectName: project?.projectName ?? null,
        executedDate: null,
        uploadedBy: { name: user?.displayName ?? user?.email ?? '', email: user?.email ?? '' },
      });
      setAgreementLabel('');
      setAgreementProjectKey('');
      setAgreementNewProjectNumber('');
      setAgreementNewProjectName('');
      listExecutedAgreements(clientId).then(setExecutedAgreements);
    } catch (err) {
      setAgreementError(err instanceof Error ? err.message : 'Upload failed.');
    } finally {
      setUploadingAgreement(false);
    }
  }

  async function handleDeleteAgreement(agreementId: string) {
    await deleteExecutedAgreement(clientId, agreementId);
    setExecutedAgreements((prev) => prev.filter((a) => a.id !== agreementId));
  }

  return (
    <div className="space-y-8">
      <div>
        <div className="flex flex-wrap items-center justify-between gap-3">
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
          </div>
          <Link href={`/?clientName=${encodeURIComponent(client.name)}`}>
            <Button variant="secondary">+ Upload contract</Button>
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

      <Card className="p-5">
        <p className="mb-3 font-mono text-[11px] uppercase tracking-wide text-ink-faint">Executed agreements</p>
        {executedAgreements.length > 0 && (
          <div className="mb-4 space-y-2">
            {executedAgreements.map((a) => (
              <div
                key={a.id}
                className="flex items-center justify-between border-b border-rule pb-2 last:border-0 last:pb-0"
              >
                <div>
                  <span className="mr-2 rounded-full border border-rule px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide text-ink-faint">
                    {a.docType}
                  </span>
                  {a.projectNumber && (
                    a.contractId ? (
                      <a
                        href={`#matter-${a.contractId}`}
                        className="mr-2 font-mono text-[10px] text-ink-faint hover:text-ink hover:underline"
                      >
                        {a.projectNumber} — {a.projectName}
                      </a>
                    ) : (
                      <span className="mr-2 font-mono text-[10px] text-ink-faint">
                        {a.projectNumber} — {a.projectName}
                      </span>
                    )
                  )}
                  <a
                    href={a.driveUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="font-body text-sm text-accent hover:underline"
                  >
                    {a.label || a.docType} ↗
                  </a>
                  {a.driveFolderUrl && (
                    <a
                      href={a.driveFolderUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="ml-2 font-mono text-[10px] text-ink-faint hover:text-ink hover:underline"
                    >
                      Folder ↗
                    </a>
                  )}
                </div>
                <button
                  type="button"
                  onClick={() => handleDeleteAgreement(a.id)}
                  className="font-mono text-xs text-ink-faint hover:text-high"
                >
                  Remove
                </button>
              </div>
            ))}
          </div>
        )}
        <div className="flex flex-wrap items-end gap-3">
          <label className="block">
            <span className="mb-1 block font-mono text-xs uppercase text-ink-faint">Type</span>
            <select
              value={agreementDocType}
              onChange={(e) => setAgreementDocType(e.target.value as DocType)}
              className="border border-rule px-3 py-2 text-sm"
            >
              <option value="MSA">MSA</option>
              <option value="SOW">SOW</option>
              <option value="Change Order">Change Order</option>
              <option value="Other">Other</option>
            </select>
          </label>
          <label className="block">
            <span className="mb-1 block font-mono text-xs uppercase text-ink-faint">
              Project{REQUIRES_PROJECT.includes(agreementDocType) ? '' : ' (optional)'}
            </span>
            <select
              value={agreementProjectKey}
              onChange={(e) => setAgreementProjectKey(e.target.value)}
              className="border border-rule px-3 py-2 text-sm"
            >
              <option value="">— none (client-level) —</option>
              {projectOptions.map((p) => {
                const key = `${p.projectNumber}—${p.projectName}`;
                return (
                  <option key={key} value={key}>
                    {p.projectNumber} — {p.projectName}
                  </option>
                );
              })}
              <option value="__new__">+ New project…</option>
            </select>
          </label>
          {agreementProjectKey === '__new__' && (
            <>
              <label className="block">
                <span className="mb-1 block font-mono text-xs uppercase text-ink-faint">Job number</span>
                <input
                  value={agreementNewProjectNumber}
                  onChange={(e) => setAgreementNewProjectNumber(e.target.value)}
                  className="w-28 border border-rule px-3 py-2 text-sm"
                />
              </label>
              <label className="block">
                <span className="mb-1 block font-mono text-xs uppercase text-ink-faint">Project name</span>
                <input
                  value={agreementNewProjectName}
                  onChange={(e) => setAgreementNewProjectName(e.target.value)}
                  className="w-48 border border-rule px-3 py-2 text-sm"
                />
              </label>
            </>
          )}
          <label className="block flex-1">
            <span className="mb-1 block font-mono text-xs uppercase text-ink-faint">
              Label (optional — e.g. &quot;Change Order #2&quot;)
            </span>
            <input
              value={agreementLabel}
              onChange={(e) => setAgreementLabel(e.target.value)}
              className="w-full border border-rule px-3 py-2 text-sm"
            />
          </label>
          <label className="cursor-pointer rounded-sm border border-rule px-3 py-1.5 font-mono text-xs uppercase tracking-wide text-ink-soft hover:border-ink">
            {uploadingAgreement ? 'Uploading…' : 'Upload executed file'}
            <input type="file" className="hidden" onChange={handleUploadAgreement} disabled={uploadingAgreement} />
          </label>
        </div>
        {agreementError && <p className="mt-2 text-sm text-high">{agreementError}</p>}
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
              hasExecutedAgreement={executedAgreements.some((a) => a.contractId === c.id)}
              onToggleMarkedReceived={() => handleToggleMarkedReceived(c.id, !c.markedReceived)}
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
