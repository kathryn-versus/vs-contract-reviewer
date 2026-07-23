'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { Card } from '@/components/ui/Card';
import { useAuth } from '@/hooks/useAuth';
import {
  listClients,
  listAllContracts,
  listAllExecutedAgreements,
  setContractMarkedReceived,
  setContractWorkflowStatus,
  addExecutedAgreement,
} from '@/lib/firebase/firestore';
import type { ClientDoc, ContractDoc } from '@/lib/types';

type EditableStatus = 'open' | 'ready_for_execution' | 'out_for_signature' | 'received';
type DisplayStatus = EditableStatus | 'executed';
type FilterValue = 'all' | 'open' | 'ready_for_execution' | 'out_for_signature' | 'closed';

const STATUS_OPTIONS: { value: EditableStatus; label: string }[] = [
  { value: 'open', label: 'Open' },
  { value: 'ready_for_execution', label: 'Ready for execution' },
  { value: 'out_for_signature', label: 'Out for signature' },
  { value: 'received', label: 'Received' },
];

const STATUS_LABELS: Record<DisplayStatus, string> = {
  open: 'Open',
  ready_for_execution: 'Ready for execution',
  out_for_signature: 'Out for signature',
  received: 'Received',
  executed: 'Executed',
};

// Neutral (not started) → amber (needs your action) → outlined accent
// (waiting on the counterparty) → green (done) — a rough left-to-right
// progression rather than an arbitrary color per status.
const STATUS_CLASSES: Record<DisplayStatus, string> = {
  open: 'border-rule text-ink-faint',
  ready_for_execution: 'border-med/30 bg-med-bg text-med',
  out_for_signature: 'border-accent/30 text-accent',
  received: 'border-low/30 bg-low-bg text-low',
  executed: 'border-low/30 bg-low-bg text-low',
};

const FILTERS: { value: FilterValue; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'open', label: 'Open' },
  { value: 'ready_for_execution', label: 'Ready for execution' },
  { value: 'out_for_signature', label: 'Out for signature' },
  { value: 'closed', label: 'Received / executed' },
];

function daysAgo(ms: number): string {
  const days = Math.max(0, Math.floor((Date.now() - ms) / (1000 * 60 * 60 * 24)));
  if (days === 0) return 'today';
  if (days === 1) return '1 day ago';
  return `${days} days ago`;
}

interface Row {
  contract: ContractDoc;
  status: DisplayStatus;
}

// The Library's default landing view — a flat, filterable table of every
// contract across every client, so tracking what's still outstanding
// doesn't mean clicking into each client one at a time. The per-client card
// grid (ClientListView) is still available as the "Clients" tab for
// browsing, editing client-level details, or reaching a client with no
// contracts on file yet.
export function ContractsTracker() {
  const { user } = useAuth();
  const [clients, setClients] = useState<ClientDoc[]>([]);
  const [contracts, setContracts] = useState<ContractDoc[]>([]);
  const [executedContractIds, setExecutedContractIds] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<FilterValue>('all');
  const [sortBy, setSortBy] = useState<'oldest' | 'client'>('oldest');
  const [uploadingId, setUploadingId] = useState<string | null>(null);

  async function refresh() {
    setLoading(true);
    try {
      const [clientsList, contractsList, agreements] = await Promise.all([
        listClients(),
        listAllContracts(),
        listAllExecutedAgreements(),
      ]);
      setClients(clientsList);
      setContracts(contractsList);
      setExecutedContractIds(
        new Set(agreements.map((a) => a.contractId).filter((id): id is string => Boolean(id)))
      );
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    refresh();
  }, []);

  const rows: Row[] = useMemo(
    () =>
      contracts.map((contract) => ({
        contract,
        status: executedContractIds.has(contract.id)
          ? 'executed'
          : contract.markedReceived
          ? 'received'
          : contract.workflowStatus ?? 'open',
      })),
    [contracts, executedContractIds]
  );

  // KPIs — deliberately just these two: clients with no MSA addressed yet
  // (a real gap), and the total count of anything not yet closed, across
  // every in-progress stage (open, ready for execution, out for signature).
  const missingMsaCount = clients.filter((c) => !c.msaContractId && !c.msaDriveFileId && !c.noMsa).length;
  const openCount = rows.filter((r) => r.status !== 'executed' && r.status !== 'received').length;

  const filteredRows = useMemo(() => {
    const term = search.trim().toLowerCase();
    let list = rows.filter((r) => {
      if (filter === 'all') return true;
      if (filter === 'closed') return r.status === 'executed' || r.status === 'received';
      return r.status === filter;
    });
    if (term) {
      list = list.filter(
        (r) =>
          r.contract.clientName.toLowerCase().includes(term) ||
          r.contract.projectName.toLowerCase().includes(term) ||
          r.contract.projectNumber.toLowerCase().includes(term)
      );
    }
    return [...list].sort((a, b) =>
      sortBy === 'oldest'
        ? a.contract.createdAt - b.contract.createdAt
        : a.contract.clientName.localeCompare(b.contract.clientName)
    );
  }, [rows, filter, search, sortBy]);

  async function handleStatusChange(row: Row, next: EditableStatus) {
    const { contract } = row;
    if (next === 'received') {
      await setContractMarkedReceived(contract.id, true);
    } else {
      if (contract.markedReceived) {
        await setContractMarkedReceived(contract.id, false);
      }
      await setContractWorkflowStatus(contract.id, next);
    }
    refresh();
  }

  // Files a signed copy straight against this row's project — same
  // Executed-agreements flow as the client page, just reachable without
  // navigating there first. Auto marks the matter received on success, same
  // as every other executed-filing path in the app.
  async function handleUpload(row: Row, file: File) {
    const { contract } = row;
    setUploadingId(contract.id);
    try {
      const form = new FormData();
      form.append('file', file);
      form.append('clientName', contract.clientName);
      form.append('docType', contract.docType);
      form.append('label', '');
      form.append('projectNumber', contract.projectNumber);
      form.append('projectName', contract.projectName);
      const res = await fetch('/api/drive/upload-executed-agreement', { method: 'POST', body: form });
      const data = await res.json();
      if (data.error) throw new Error(data.error);
      await addExecutedAgreement(contract.clientId, {
        docType: contract.docType,
        label: '',
        driveFileId: data.driveFileId,
        driveUrl: data.driveUrl,
        driveFolderUrl: data.driveFolderUrl ?? null,
        contractId: contract.id,
        projectNumber: contract.projectNumber,
        projectName: contract.projectName,
        executedDate: null,
        uploadedBy: { name: user?.displayName ?? user?.email ?? '', email: user?.email ?? '' },
      });
      await setContractMarkedReceived(contract.id, true);
      await refresh();
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Upload failed.');
    } finally {
      setUploadingId(null);
    }
  }

  if (loading) {
    return <p className="font-mono text-sm text-ink-faint">Loading contracts…</p>;
  }

  return (
    <div>
      <div className="mb-6 grid grid-cols-2 gap-3 sm:max-w-md">
        <Card className="p-4">
          <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">Missing MSA</p>
          <p className="mt-1 font-display text-2xl text-ink">{missingMsaCount}</p>
        </Card>
        <Card className="p-4">
          <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">Open</p>
          <p className="mt-1 font-display text-2xl text-ink">{openCount}</p>
        </Card>
      </div>

      <div className="mb-4 flex flex-wrap items-center gap-2">
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search client, job, or job number…"
          className="min-w-[220px] flex-1 border border-rule px-3 py-2 text-sm outline-none focus:border-ink"
        />
        <div className="flex flex-wrap gap-1.5">
          {FILTERS.map((f) => (
            <button
              key={f.value}
              type="button"
              onClick={() => setFilter(f.value)}
              className={
                filter === f.value
                  ? 'rounded-sm border border-ink px-3 py-1.5 font-mono text-xs uppercase tracking-wide text-ink'
                  : 'rounded-sm border border-rule px-3 py-1.5 font-mono text-xs uppercase tracking-wide text-ink-faint hover:border-ink hover:text-ink'
              }
            >
              {f.label}
            </button>
          ))}
        </div>
        <select
          value={sortBy}
          onChange={(e) => setSortBy(e.target.value as 'oldest' | 'client')}
          className="border border-rule px-3 py-2 text-sm"
        >
          <option value="oldest">Oldest first</option>
          <option value="client">Client A–Z</option>
        </select>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full border-collapse text-sm">
          <thead>
            <tr className="border-b border-rule text-left font-mono text-[11px] uppercase tracking-wide text-ink-faint">
              <th className="px-2 py-2">Client</th>
              <th className="px-2 py-2">Project</th>
              <th className="px-2 py-2">Type</th>
              <th className="px-2 py-2">Status</th>
              <th className="px-2 py-2">Filed</th>
              <th className="px-2 py-2 text-right">Upload</th>
            </tr>
          </thead>
          <tbody>
            {filteredRows.map((row) => (
              <tr key={row.contract.id} className="border-b border-rule">
                <td className="px-2 py-2">
                  <Link href={`/library/${row.contract.clientId}`} className="text-ink hover:underline">
                    {row.contract.clientName}
                  </Link>
                </td>
                <td className="px-2 py-2">
                  <Link
                    href={`/library/${row.contract.clientId}#matter-${row.contract.id}`}
                    className="text-ink-soft hover:underline"
                  >
                    {row.contract.projectNumber} — {row.contract.projectName}
                  </Link>
                </td>
                <td className="px-2 py-2 font-mono text-xs text-ink-faint">{row.contract.docType}</td>
                <td className="px-2 py-2">
                  {row.status === 'executed' ? (
                    <span
                      title="Linked to a signed file in Executed agreements — remove it there to reopen"
                      className={`inline-block rounded-full border px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide ${STATUS_CLASSES.executed}`}
                    >
                      {STATUS_LABELS.executed}
                    </span>
                  ) : (
                    <select
                      value={row.status}
                      onChange={(e) => handleStatusChange(row, e.target.value as EditableStatus)}
                      className={`rounded-full border bg-paper px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide ${STATUS_CLASSES[row.status]}`}
                    >
                      {STATUS_OPTIONS.map((opt) => (
                        <option key={opt.value} value={opt.value}>
                          {opt.label}
                        </option>
                      ))}
                    </select>
                  )}
                </td>
                <td className="px-2 py-2 font-mono text-xs text-ink-faint">{daysAgo(row.contract.createdAt)}</td>
                <td className="px-2 py-2 text-right">
                  <label className="inline-block cursor-pointer rounded-sm border border-rule px-2 py-1 font-mono text-xs uppercase tracking-wide text-ink-faint hover:border-ink hover:text-ink">
                    {uploadingId === row.contract.id ? 'Uploading…' : 'Upload'}
                    <input
                      type="file"
                      className="hidden"
                      disabled={uploadingId === row.contract.id}
                      onChange={(e) => {
                        const file = e.target.files?.[0];
                        e.target.value = '';
                        if (file) handleUpload(row, file);
                      }}
                    />
                  </label>
                </td>
              </tr>
            ))}
            {filteredRows.length === 0 && (
              <tr>
                <td colSpan={6} className="px-2 py-8 text-center font-mono text-sm text-ink-faint">
                  No contracts match this filter.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
