'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { Button } from '@/components/ui/Button';
import { Combobox } from '@/components/ui/Combobox';
import { useAuth } from '@/hooks/useAuth';
import {
  listClients,
  getOrCreateClient,
  ensureClientDriveFolder,
  createContract,
  addVersion,
  updateContractDrive,
  updateVersionDrive,
} from '@/lib/firebase/firestore';
import type { ClientDoc, DocType } from '@/lib/types';

const DOC_TYPES: DocType[] = ['MSA', 'SOW', 'MSA+SOW', 'Other'];

interface BatchRow {
  id: string;
  file: File;
  clientName: string;
  projectName: string;
  projectNumber: string;
  docType: DocType;
  status: 'pending' | 'uploading' | 'done' | 'error';
  error?: string;
}

// Turns "Acme_MSA_2023.pdf" into "Acme MSA 2023" — just a starting point the
// reviewer can edit, not meant to be authoritative.
function guessProjectName(fileName: string): string {
  const withoutExt = fileName.replace(/\.[^.]+$/, '');
  return withoutExt.replace(/[_-]+/g, ' ').trim();
}

export function BatchImportView() {
  const { user } = useAuth();
  const [clients, setClients] = useState<ClientDoc[]>([]);
  const [defaultClient, setDefaultClient] = useState('');
  const [rows, setRows] = useState<BatchRow[]>([]);
  const [importing, setImporting] = useState(false);

  useEffect(() => {
    listClients().then(setClients).catch(() => {});
  }, []);

  function handleFiles(fileList: FileList | null) {
    if (!fileList) return;
    const newRows: BatchRow[] = Array.from(fileList).map((file) => ({
      id: `${file.name}-${file.size}-${file.lastModified}-${Math.random().toString(36).slice(2, 7)}`,
      file,
      clientName: defaultClient,
      projectName: guessProjectName(file.name),
      projectNumber: '',
      docType: 'Other',
      status: 'pending',
    }));
    setRows((prev) => [...prev, ...newRows]);
  }

  function updateRow(id: string, patch: Partial<BatchRow>) {
    setRows((prev) => prev.map((r) => (r.id === id ? { ...r, ...patch } : r)));
  }

  function removeRow(id: string) {
    setRows((prev) => prev.filter((r) => r.id !== id));
  }

  function applyDefaultClientToAll() {
    setRows((prev) => prev.map((r) => ({ ...r, clientName: defaultClient })));
  }

  const readyCount = rows.filter(
    (r) => r.status !== 'done' && r.clientName.trim() && r.projectName.trim() && r.projectNumber.trim()
  ).length;
  const doneCount = rows.filter((r) => r.status === 'done').length;
  const errorCount = rows.filter((r) => r.status === 'error').length;

  async function importAll() {
    if (!user?.email) return;
    setImporting(true);
    for (const row of rows) {
      if (row.status === 'done') continue;
      if (!row.clientName.trim() || !row.projectName.trim() || !row.projectNumber.trim()) continue;
      updateRow(row.id, { status: 'uploading', error: undefined });
      try {
        // 1. Resolve/create the client + their Drive folder.
        const client = await getOrCreateClient(row.clientName.trim(), user.email);
        await ensureClientDriveFolder(client);

        // 2. Create the matter + first version — filed without review,
        //    matching the "File for reference" default (brief: archived
        //    contracts don't need Claude analysis to be usefully catalogued).
        const contractId = await createContract({
          clientId: client.id,
          clientName: client.name,
          projectName: row.projectName.trim(),
          projectNumber: row.projectNumber.trim(),
          docType: row.docType,
          counterparty: client.name,
          submittedBy: {
            uid: user.uid,
            name: user.displayName ?? user.email ?? '',
            email: user.email ?? '',
          },
          driveFileId: null,
          driveUrl: null,
          driveFolderUrl: null,
          driveFolderId: null,
        });

        const versionId = await addVersion(contractId, {
          versionNumber: 1,
          uploadedBy: { name: user.displayName ?? user.email ?? '', email: user.email ?? '' },
          fileName: row.file.name,
          characterCount: 0,
          findings: [],
          insuranceRequirements: [],
          deltaFromPrevious: null,
          reviewed: false,
          driveFileId: null,
          driveUrl: null,
          driveFolderId: null,
          driveFolderUrl: null,
          googleDocId: null,
          googleDocUrl: null,
          reportHtmlUrl: null,
          reportPdfUrl: null,
        });

        // 3. Upload to Drive — reuses the same route the normal intake flow
        //    uses, so it lands in the same Client/Job/dated-folder structure.
        const form = new FormData();
        form.append('file', row.file);
        form.append('clientName', client.name);
        form.append('projectName', row.projectName.trim());
        form.append('projectNumber', row.projectNumber.trim());
        const driveRes = await fetch('/api/drive/upload', { method: 'POST', body: form });
        const driveData = await driveRes.json();
        if (driveData.error) throw new Error(driveData.error);

        await updateContractDrive(contractId, driveData);
        await updateVersionDrive(contractId, versionId, {
          driveFileId: driveData.driveFileId ?? null,
          driveUrl: driveData.driveUrl ?? null,
          driveFolderId: driveData.driveFolderId ?? null,
          driveFolderUrl: driveData.driveFolderUrl ?? null,
        });

        updateRow(row.id, { status: 'done' });
      } catch (err) {
        updateRow(row.id, {
          status: 'error',
          error: err instanceof Error ? err.message : 'Import failed.',
        });
      }
    }
    setImporting(false);
  }

  if (!user) return null;

  return (
    <div>
      <div className="mb-2 flex items-baseline justify-between">
        <h1 className="font-display text-2xl text-ink">Batch import</h1>
        <Link href="/library" className="font-mono text-xs text-accent hover:underline">
          ← Back to Library
        </Link>
      </div>
      <p className="mb-6 font-body text-sm text-ink-soft">
        Bulk-file archived contracts straight to Drive — no Claude review runs on these, matching
        the &quot;File for reference&quot; flow. Good for catching up a backlog rather than
        reviewing one at a time.
      </p>

      <div className="mb-6 space-y-4 rounded-sm border border-rule bg-paper p-5">
        <label className="block">
          <span className="mb-1.5 block font-mono text-xs uppercase tracking-wide text-ink-faint">
            Default client (applied to files as you add them)
          </span>
          <div className="flex items-center gap-2">
            <div className="flex-1">
              <Combobox
                value={defaultClient}
                onChange={setDefaultClient}
                options={clients.map((c) => ({ id: c.id, label: c.name }))}
                onSelect={(o) => setDefaultClient(o.label)}
                placeholder="Choose or type a client…"
              />
            </div>
            {rows.length > 0 && (
              <Button variant="ghost" onClick={applyDefaultClientToAll} disabled={!defaultClient.trim()}>
                Apply to all rows
              </Button>
            )}
          </div>
        </label>

        <label className="block">
          <span className="mb-1.5 block font-mono text-xs uppercase tracking-wide text-ink-faint">
            Add files
          </span>
          <input
            type="file"
            multiple
            accept=".pdf,.docx,.txt"
            onChange={(e) => {
              handleFiles(e.target.files);
              e.target.value = '';
            }}
            className="block w-full font-body text-sm"
          />
        </label>
      </div>

      {rows.length > 0 && (
        <>
          <div className="overflow-x-auto rounded-sm border border-rule">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-rule bg-accent-soft/10 text-left font-mono text-[11px] uppercase tracking-wide text-ink-faint">
                  <th className="px-3 py-2">File</th>
                  <th className="px-3 py-2">Client</th>
                  <th className="px-3 py-2">Job name</th>
                  <th className="px-3 py-2">Job number</th>
                  <th className="px-3 py-2">Doc type</th>
                  <th className="px-3 py-2">Status</th>
                  <th className="px-3 py-2" />
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr key={row.id} className="border-b border-rule last:border-0">
                    <td className="max-w-[160px] truncate px-3 py-2 font-body text-ink" title={row.file.name}>
                      {row.file.name}
                    </td>
                    <td className="px-3 py-2">
                      <Combobox
                        value={row.clientName}
                        onChange={(v) => updateRow(row.id, { clientName: v })}
                        options={clients.map((c) => ({ id: c.id, label: c.name }))}
                        onSelect={(o) => updateRow(row.id, { clientName: o.label })}
                        placeholder="Client…"
                      />
                    </td>
                    <td className="px-3 py-2">
                      <input
                        value={row.projectName}
                        onChange={(e) => updateRow(row.id, { projectName: e.target.value })}
                        placeholder="Job name"
                        className="w-full border border-rule px-2 py-1 text-sm"
                      />
                    </td>
                    <td className="px-3 py-2">
                      <input
                        value={row.projectNumber}
                        onChange={(e) => updateRow(row.id, { projectNumber: e.target.value })}
                        placeholder="e.g. VS26153"
                        className="w-full border border-rule px-2 py-1 text-sm"
                      />
                    </td>
                    <td className="px-3 py-2">
                      <select
                        value={row.docType}
                        onChange={(e) => updateRow(row.id, { docType: e.target.value as DocType })}
                        className="w-full border border-rule px-2 py-1 text-sm"
                      >
                        {DOC_TYPES.map((t) => (
                          <option key={t} value={t}>
                            {t}
                          </option>
                        ))}
                      </select>
                    </td>
                    <td className="px-3 py-2 font-mono text-xs">
                      {row.status === 'pending' && <span className="text-ink-faint">Ready</span>}
                      {row.status === 'uploading' && <span className="text-med">Filing…</span>}
                      {row.status === 'done' && <span className="text-low">Filed ✓</span>}
                      {row.status === 'error' && (
                        <span className="text-high" title={row.error}>
                          Failed
                        </span>
                      )}
                    </td>
                    <td className="px-3 py-2">
                      <button
                        onClick={() => removeRow(row.id)}
                        disabled={row.status === 'uploading'}
                        className="font-mono text-xs text-ink-faint hover:text-high disabled:opacity-40"
                      >
                        Remove
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="mt-4 flex items-center justify-between">
            <p className="font-mono text-xs text-ink-faint">
              {readyCount} ready to import
              {doneCount > 0 && ` · ${doneCount} filed`}
              {errorCount > 0 && ` · ${errorCount} failed`}
            </p>
            <Button variant="primary" onClick={importAll} disabled={importing || readyCount === 0}>
              {importing ? 'Importing…' : `Import all (${readyCount})`}
            </Button>
          </div>
        </>
      )}
    </div>
  );
}
