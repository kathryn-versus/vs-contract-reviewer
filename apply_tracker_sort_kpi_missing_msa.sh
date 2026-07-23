#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_tracker_sort_kpi_missing_msa.sh
set -e

python3 - << 'PYEOF'
import os
path = "src/components/library/ContractsTracker.tsx"
with open(path) as f:
    existing = f.read()

if "missing_msa" in existing:
    print("ContractsTracker.tsx: already present — nothing to do.")
    raise SystemExit(0)

content = '''\'use client\';

import { useMemo, useState, useEffect } from \'react\';
import Link from \'next/link\';
import { Card } from \'@/components/ui/Card\';
import { useAuth } from \'@/hooks/useAuth\';
import {
  listClients,
  listAllContracts,
  listAllExecutedAgreements,
  setContractMarkedReceived,
  setContractWorkflowStatus,
  addExecutedAgreement,
  setClientMsaFile,
} from \'@/lib/firebase/firestore\';
import type { ClientDoc, ContractDoc } from \'@/lib/types\';

type EditableStatus = \'open\' | \'ready_for_execution\' | \'out_for_signature\' | \'received\';
type DisplayStatus = EditableStatus | \'executed\';
// \'in_progress\' and \'missing_msa\' aren\'t pill buttons — they\'re only reachable
// by clicking the matching KPI card, kept as filter values so the same
// state drives both entry points.
type FilterValue = \'all\' | \'open\' | \'ready_for_execution\' | \'out_for_signature\' | \'closed\' | \'in_progress\' | \'missing_msa\';
type SortKey = \'client\' | \'type\' | \'status\' | \'filed\';

const STATUS_OPTIONS: { value: EditableStatus; label: string }[] = [
  { value: \'open\', label: \'Open\' },
  { value: \'ready_for_execution\', label: \'Ready for execution\' },
  { value: \'out_for_signature\', label: \'Out for signature\' },
  { value: \'received\', label: \'Received\' },
];

const STATUS_LABELS: Record<DisplayStatus, string> = {
  open: \'Open\',
  ready_for_execution: \'Ready for execution\',
  out_for_signature: \'Out for signature\',
  received: \'Received\',
  executed: \'Executed\',
};

// Neutral (not started) → amber (needs your action) → outlined accent
// (waiting on the counterparty) → green (done) — a rough left-to-right
// progression rather than an arbitrary color per status.
const STATUS_CLASSES: Record<DisplayStatus, string> = {
  open: \'border-rule text-ink-faint\',
  ready_for_execution: \'border-med/30 bg-med-bg text-med\',
  out_for_signature: \'border-accent/30 text-accent\',
  received: \'border-low/30 bg-low-bg text-low\',
  executed: \'border-low/30 bg-low-bg text-low\',
};

// Sort order for the Status column — roughly the same left-to-right
// progression as STATUS_CLASSES, so "sort by status" groups stages together
// in a sensible order rather than an arbitrary one.
const STATUS_RANK: Record<DisplayStatus, number> = {
  open: 0,
  ready_for_execution: 1,
  out_for_signature: 2,
  received: 3,
  executed: 4,
};

const FILTERS: { value: FilterValue; label: string }[] = [
  { value: \'all\', label: \'All\' },
  { value: \'open\', label: \'Open\' },
  { value: \'ready_for_execution\', label: \'Ready for execution\' },
  { value: \'out_for_signature\', label: \'Out for signature\' },
  { value: \'closed\', label: \'Received / executed\' },
];

function daysAgo(ms: number): string {
  const days = Math.max(0, Math.floor((Date.now() - ms) / (1000 * 60 * 60 * 24)));
  if (days === 0) return \'today\';
  if (days === 1) return \'1 day ago\';
  return `${days} days ago`;
}

interface Row {
  contract: ContractDoc;
  status: DisplayStatus;
}

function SortHeader({
  label,
  sortKeyValue,
  activeKey,
  dir,
  onSort,
}: {
  label: string;
  sortKeyValue: SortKey;
  activeKey: SortKey;
  dir: \'asc\' | \'desc\';
  onSort: (key: SortKey) => void;
}) {
  const active = activeKey === sortKeyValue;
  return (
    <th
      className="cursor-pointer select-none px-2 py-2 hover:text-ink"
      onClick={() => onSort(sortKeyValue)}
    >
      {label}
      {active ? (dir === \'asc\' ? \' ↑\' : \' ↓\') : \'\'}
    </th>
  );
}

// The Library\'s default landing view — a flat, filterable, sortable table of
// every contract across every client, so tracking what\'s still outstanding
// doesn\'t mean clicking into each client one at a time. The per-client card
// grid (ClientListView) is still available as the "Clients" tab for
// browsing, editing client-level details, or reaching a client with no
// contracts on file yet.
export function ContractsTracker() {
  const { user } = useAuth();
  const [clients, setClients] = useState<ClientDoc[]>([]);
  const [contracts, setContracts] = useState<ContractDoc[]>([]);
  const [executedContractIds, setExecutedContractIds] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [search, setSearch] = useState(\'\');
  const [filter, setFilter] = useState<FilterValue>(\'all\');
  const [sortKey, setSortKey] = useState<SortKey>(\'filed\');
  const [sortDir, setSortDir] = useState<\'asc\' | \'desc\'>(\'asc\');
  const [uploadingId, setUploadingId] = useState<string | null>(null);

  // Each of the three loads independently (allSettled, not all) so one
  // failing — say a permissions issue on just one collection — doesn\'t blank
  // out the whole page silently. Any failure is logged AND shown on screen,
  // since a query that quietly returns nothing looks identical to "there\'s
  // truly no data" otherwise.
  async function refresh() {
    setLoading(true);
    setLoadError(null);
    try {
      const [clientsResult, contractsResult, agreementsResult] = await Promise.allSettled([
        listClients(),
        listAllContracts(),
        listAllExecutedAgreements(),
      ]);
      if (clientsResult.status === \'fulfilled\') setClients(clientsResult.value);
      if (contractsResult.status === \'fulfilled\') setContracts(contractsResult.value);
      if (agreementsResult.status === \'fulfilled\') {
        setExecutedContractIds(
          new Set(agreementsResult.value.map((a) => a.contractId).filter((id): id is string => Boolean(id)))
        );
      }
      const failures = [
        [\'clients\', clientsResult] as const,
        [\'contracts\', contractsResult] as const,
        [\'executed agreements\', agreementsResult] as const,
      ].filter(([, r]) => r.status === \'rejected\');
      if (failures.length > 0) {
        failures.forEach(([label, r]) => console.error(`ContractsTracker: failed to load ${label}`, (r as PromiseRejectedResult).reason));
        setLoadError(
          failures
            .map(([label, r]) => {
              const reason = (r as PromiseRejectedResult).reason;
              const message = reason instanceof Error ? reason.message : String(reason);
              return `${label}: ${message}`;
            })
            .join(\' — \')
        );
      }
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
          ? \'executed\'
          : contract.markedReceived
          ? \'received\'
          : contract.workflowStatus ?? \'open\',
      })),
    [contracts, executedContractIds]
  );

  const missingMsaClients = useMemo(
    () => clients.filter((c) => !c.msaContractId && !c.msaDriveFileId && !c.noMsa),
    [clients]
  );

  // KPIs — deliberately just these two: clients with no MSA addressed yet
  // (a real gap), and the total count of anything not yet closed, across
  // every in-progress stage (open, ready for execution, out for signature).
  // Both are clickable — they set the same filter state the pill buttons
  // use, just reaching filter values ("in_progress", "missing_msa") that
  // aren\'t exposed as their own pills.
  const missingMsaCount = missingMsaClients.length;
  const openCount = rows.filter((r) => r.status !== \'executed\' && r.status !== \'received\').length;

  function handleSort(key: SortKey) {
    if (sortKey === key) {
      setSortDir((d) => (d === \'asc\' ? \'desc\' : \'asc\'));
    } else {
      setSortKey(key);
      setSortDir(\'asc\');
    }
  }

  const filteredRows = useMemo(() => {
    const term = search.trim().toLowerCase();
    let list = rows.filter((r) => {
      if (filter === \'all\') return true;
      if (filter === \'closed\') return r.status === \'executed\' || r.status === \'received\';
      if (filter === \'in_progress\') return r.status !== \'executed\' && r.status !== \'received\';
      if (filter === \'missing_msa\') return false;
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
    return [...list].sort((a, b) => {
      let result = 0;
      if (sortKey === \'client\') result = a.contract.clientName.localeCompare(b.contract.clientName);
      else if (sortKey === \'type\') result = a.contract.docType.localeCompare(b.contract.docType);
      else if (sortKey === \'status\') result = STATUS_RANK[a.status] - STATUS_RANK[b.status];
      else result = a.contract.createdAt - b.contract.createdAt;
      return sortDir === \'asc\' ? result : -result;
    });
  }, [rows, filter, search, sortKey, sortDir]);

  const filteredMissingMsaClients = useMemo(() => {
    const term = search.trim().toLowerCase();
    const list = term ? missingMsaClients.filter((c) => c.name.toLowerCase().includes(term)) : missingMsaClients;
    return [...list].sort((a, b) => a.name.localeCompare(b.name));
  }, [missingMsaClients, search]);

  async function handleStatusChange(row: Row, next: EditableStatus) {
    const { contract } = row;
    if (next === \'received\') {
      await setContractMarkedReceived(contract.id, true);
    } else {
      if (contract.markedReceived) {
        await setContractMarkedReceived(contract.id, false);
      }
      await setContractWorkflowStatus(contract.id, next);
    }
    refresh();
  }

  // Files a signed copy straight against this row\'s project — same
  // Executed-agreements flow as the client page, just reachable without
  // navigating there first. Auto marks the matter received on success, same
  // as every other executed-filing path in the app.
  async function handleUpload(row: Row, file: File) {
    const { contract } = row;
    setUploadingId(contract.id);
    try {
      const form = new FormData();
      form.append(\'file\', file);
      form.append(\'clientName\', contract.clientName);
      form.append(\'docType\', contract.docType);
      form.append(\'label\', \'\');
      form.append(\'projectNumber\', contract.projectNumber);
      form.append(\'projectName\', contract.projectName);
      const res = await fetch(\'/api/drive/upload-executed-agreement\', { method: \'POST\', body: form });
      const data = await res.json();
      if (data.error) throw new Error(data.error);
      await addExecutedAgreement(contract.clientId, {
        docType: contract.docType,
        label: \'\',
        driveFileId: data.driveFileId,
        driveUrl: data.driveUrl,
        driveFolderUrl: data.driveFolderUrl ?? null,
        contractId: contract.id,
        projectNumber: contract.projectNumber,
        projectName: contract.projectName,
        executedDate: null,
        uploadedBy: { name: user?.displayName ?? user?.email ?? \'\', email: user?.email ?? \'\' },
      });
      await setContractMarkedReceived(contract.id, true);
      await refresh();
    } catch (err) {
      alert(err instanceof Error ? err.message : \'Upload failed.\');
    } finally {
      setUploadingId(null);
    }
  }

  // Uploads straight into the client\'s Governing MSA slot — the same
  // no-analysis direct-upload flow as the client page\'s "Upload MSA"
  // control, just reachable from the missing-MSA row instead of having to
  // navigate to that client first.
  async function handleUploadMsa(client: ClientDoc, file: File) {
    setUploadingId(client.id);
    try {
      const form = new FormData();
      form.append(\'file\', file);
      form.append(\'clientName\', client.name);
      const res = await fetch(\'/api/drive/upload-msa\', { method: \'POST\', body: form });
      const data = await res.json();
      if (data.error) throw new Error(data.error);
      await setClientMsaFile(client.id, { msaDriveFileId: data.msaDriveFileId, msaDriveUrl: data.msaDriveUrl });
      await refresh();
    } catch (err) {
      alert(err instanceof Error ? err.message : \'MSA upload failed.\');
    } finally {
      setUploadingId(null);
    }
  }

  if (loading) {
    return <p className="font-mono text-sm text-ink-faint">Loading contracts…</p>;
  }

  const showingMissingMsa = filter === \'missing_msa\';

  return (
    <div>
      {loadError && (
        <p className="mb-4 border border-high bg-high-bg px-3 py-2 text-sm text-high">
          Could not load everything: {loadError}
        </p>
      )}
      <div className="mb-6 grid grid-cols-2 gap-3 sm:max-w-md">
        <Card
          className={
            showingMissingMsa ? \'cursor-pointer p-4 ring-2 ring-accent\' : \'cursor-pointer p-4 hover:border-ink\'
          }
          onClick={() => setFilter(\'missing_msa\')}
        >
          <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">Missing MSA</p>
          <p className="mt-1 font-display text-2xl text-ink">{missingMsaCount}</p>
        </Card>
        <Card
          className={
            filter === \'in_progress\' ? \'cursor-pointer p-4 ring-2 ring-accent\' : \'cursor-pointer p-4 hover:border-ink\'
          }
          onClick={() => setFilter(\'in_progress\')}
        >
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
                  ? \'rounded-sm border border-ink px-3 py-1.5 font-mono text-xs uppercase tracking-wide text-ink\'
                  : \'rounded-sm border border-rule px-3 py-1.5 font-mono text-xs uppercase tracking-wide text-ink-faint hover:border-ink hover:text-ink\'
              }
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      {showingMissingMsa ? (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-rule text-left font-mono text-[11px] uppercase tracking-wide text-ink-faint">
                <th className="px-2 py-2">Client</th>
                <th className="px-2 py-2">Status</th>
                <th className="px-2 py-2 text-right">Upload</th>
              </tr>
            </thead>
            <tbody>
              {filteredMissingMsaClients.map((client) => (
                <tr key={client.id} className="border-b border-rule">
                  <td className="px-2 py-2">
                    <Link href={`/library/${client.id}`} className="text-ink hover:underline">
                      {client.name}
                    </Link>
                  </td>
                  <td className="px-2 py-2">
                    <span className="inline-block rounded-full border border-med/30 bg-med-bg px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide text-med">
                      Missing MSA
                    </span>
                  </td>
                  <td className="px-2 py-2 text-right">
                    <label className="inline-block cursor-pointer rounded-sm border border-rule px-2 py-1 font-mono text-xs uppercase tracking-wide text-ink-faint hover:border-ink hover:text-ink">
                      {uploadingId === client.id ? \'Uploading…\' : \'Upload MSA\'}
                      <input
                        type="file"
                        accept=".pdf,.docx,.txt"
                        className="hidden"
                        disabled={uploadingId === client.id}
                        onChange={(e) => {
                          const file = e.target.files?.[0];
                          e.target.value = \'\';
                          if (file) handleUploadMsa(client, file);
                        }}
                      />
                    </label>
                  </td>
                </tr>
              ))}
              {filteredMissingMsaClients.length === 0 && (
                <tr>
                  <td colSpan={3} className="px-2 py-8 text-center font-mono text-sm text-ink-faint">
                    Every client has an MSA addressed.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-rule text-left font-mono text-[11px] uppercase tracking-wide text-ink-faint">
                <SortHeader label="Client" sortKeyValue="client" activeKey={sortKey} dir={sortDir} onSort={handleSort} />
                <th className="px-2 py-2">Project</th>
                <SortHeader label="Type" sortKeyValue="type" activeKey={sortKey} dir={sortDir} onSort={handleSort} />
                <SortHeader label="Status" sortKeyValue="status" activeKey={sortKey} dir={sortDir} onSort={handleSort} />
                <SortHeader label="Filed" sortKeyValue="filed" activeKey={sortKey} dir={sortDir} onSort={handleSort} />
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
                    {row.status === \'executed\' ? (
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
                      {uploadingId === row.contract.id ? \'Uploading…\' : \'Upload\'}
                      <input
                        type="file"
                        className="hidden"
                        disabled={uploadingId === row.contract.id}
                        onChange={(e) => {
                          const file = e.target.files?.[0];
                          e.target.value = \'\';
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
      )}
    </div>
  );
}
'''

with open(path, "w") as f:
    f.write(content)
print("ContractsTracker.tsx: rewrote with sortable columns, clickable KPIs, and a Missing MSA table.")
PYEOF

echo ""
echo "Restart your dev server and check /library (Open contracts tab):"
echo "  1. Click the 'Status', 'Type', or 'Filed' column headers — the table"
echo "     re-sorts, and clicking the same header again reverses the order"
echo "     (an ↑/↓ shows next to whichever column is active)."
echo "  2. Click the 'Open' KPI card — the table filters to everything not"
echo "     yet closed (open, ready for execution, out for signature)."
echo "  3. Click the 'Missing MSA' KPI card — the table switches to a list"
echo "     of just those clients, each with an 'Upload MSA' button that"
echo "     files it straight to that client's Governing MSA slot."
echo "  4. Click a status pill (All / Open / etc.) to leave the Missing MSA"
echo "     view and go back to the normal contracts table."
echo ""
echo "Then npm run build, commit, and push (via GitHub Desktop) to deploy."
