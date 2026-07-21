#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_library_polish.sh
set -e

# ── 1. firestore.ts — delete a whole contract, or just one version ──────────
python3 - << 'PYEOF'
path = "src/lib/firebase/firestore.ts"
with open(path) as f:
    content = f.read()

if "export async function deleteContract" in content:
    print("firestore.ts: already present — nothing to do.")
else:
    old = """export async function moveContract(
  contractId: string,
  updates: Partial<Pick<ContractDoc, 'clientId' | 'clientName' | 'projectName'>>
) {
  await updateDoc(doc(db, 'contracts', contractId), updates);
}"""
    new = """export async function moveContract(
  contractId: string,
  updates: Partial<Pick<ContractDoc, 'clientId' | 'clientName' | 'projectName'>>
) {
  await updateDoc(doc(db, 'contracts', contractId), updates);
}

// Deletes a single version (e.g. a duplicate or accidental upload) without
// touching the rest of the contract's history.
export async function deleteVersion(contractId: string, versionId: string): Promise<void> {
  await deleteDoc(doc(db, 'contracts', contractId, 'versions', versionId));
}

// Deletes an entire contract and every version under it — for a matter that
// was created/uploaded incorrectly from the start (wrong client, duplicate
// job, test upload, etc.). Only removes the Firestore records; the source
// files already uploaded to Drive are left alone, same as removing an
// executed agreement.
export async function deleteContract(contractId: string): Promise<void> {
  const versionsSnap = await getDocs(collection(db, 'contracts', contractId, 'versions'));
  await Promise.all(versionsSnap.docs.map((d) => deleteDoc(d.ref)));
  await deleteDoc(doc(db, 'contracts', contractId));
}"""
    if old not in content:
        raise SystemExit("Expected moveContract not found in firestore.ts — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("firestore.ts: added deleteVersion and deleteContract.")
PYEOF

# ── 2. MatterCard.tsx — Delete (whole contract) + Delete on each version ────
python3 - << 'PYEOF'
path = "src/components/library/MatterCard.tsx"
with open(path) as f:
    content = f.read()

if "onDelete" in content:
    print("MatterCard.tsx: already present — nothing to do.")
else:
    old_import = "import { listVersionsForContract } from '@/lib/firebase/firestore';"
    new_import = "import { listVersionsForContract, deleteVersion } from '@/lib/firebase/firestore';"
    if old_import not in content:
        raise SystemExit("Expected firestore import not found in MatterCard.tsx — aborting.")
    content = content.replace(old_import, new_import)

    old_props = """export function MatterCard({
  contract,
  onEdit,
  isGoverningMsa,
  onToggleGoverningMsa,
  autoExpand,
  hasExecutedAgreement,
  onToggleMarkedReceived,
}: {
  contract: ContractDoc;
  onEdit: () => void;
  isGoverningMsa?: boolean;
  onToggleGoverningMsa?: () => void;
  /** Expands and highlights this card on mount — set when arriving via a
   * Library search result's #matter-{id} deep link. */
  autoExpand?: boolean;
  /** True when a real executed agreement is linked to this matter — closes
   * it automatically, taking priority over the manual markedReceived flag. */
  hasExecutedAgreement?: boolean;
  /** Toggles contract.markedReceived — only meaningful when there's no
   * linked executed agreement (that path closes a matter on its own). */
  onToggleMarkedReceived?: () => void;
}) {"""
    new_props = """export function MatterCard({
  contract,
  onEdit,
  onDelete,
  isGoverningMsa,
  onToggleGoverningMsa,
  autoExpand,
  hasExecutedAgreement,
  onToggleMarkedReceived,
}: {
  contract: ContractDoc;
  onEdit: () => void;
  /** Deletes this contract and every version under it. Omit to hide the
   * Delete action entirely (e.g. for a read-only context). */
  onDelete?: () => void;
  isGoverningMsa?: boolean;
  onToggleGoverningMsa?: () => void;
  /** Expands and highlights this card on mount — set when arriving via a
   * Library search result's #matter-{id} deep link. */
  autoExpand?: boolean;
  /** True when a real executed agreement is linked to this matter — closes
   * it automatically, taking priority over the manual markedReceived flag. */
  hasExecutedAgreement?: boolean;
  /** Toggles contract.markedReceived — only meaningful when there's no
   * linked executed agreement (that path closes a matter on its own). */
  onToggleMarkedReceived?: () => void;
}) {"""
    if old_props not in content:
        raise SystemExit("Expected MatterCard props not found in MatterCard.tsx — aborting.")
    content = content.replace(old_props, new_props)

    old_versions_fetch = """  useEffect(() => {
    listVersionsForContract(contract.id).then(setVersions).catch(() => {});
  }, [contract.id]);"""
    new_versions_fetch = """  useEffect(() => {
    listVersionsForContract(contract.id).then(setVersions).catch(() => {});
  }, [contract.id]);

  async function handleDeleteVersion(versionId: string, versionNumber: number) {
    if (!window.confirm(`Delete v${versionNumber}? This can't be undone — the Drive file itself is not affected.`)) {
      return;
    }
    await deleteVersion(contract.id, versionId);
    setVersions((prev) => prev.filter((v) => v.id !== versionId));
  }"""
    if old_versions_fetch not in content:
        raise SystemExit("Expected versions-fetch effect not found in MatterCard.tsx — aborting.")
    content = content.replace(old_versions_fetch, new_versions_fetch)

    old_edit_button = """          <button
            onClick={(e) => {
              e.stopPropagation();
              onEdit();
            }}
            className="font-mono text-xs text-ink-faint hover:text-ink"
          >
            Edit
          </button>"""
    new_edit_button = """          <button
            onClick={(e) => {
              e.stopPropagation();
              onEdit();
            }}
            className="font-mono text-xs text-ink-faint hover:text-ink"
          >
            Edit
          </button>
          {onDelete && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                if (
                  window.confirm(
                    `Delete ${contract.projectName} (${contract.projectNumber}) and all ${versions.length} version(s)? This can't be undone — Drive files are not affected.`
                  )
                ) {
                  onDelete();
                }
              }}
              className="font-mono text-xs text-ink-faint hover:text-high"
            >
              Delete
            </button>
          )}"""
    if old_edit_button not in content:
        raise SystemExit("Expected Edit button not found in MatterCard.tsx — aborting.")
    content = content.replace(old_edit_button, new_edit_button)

    old_version_row = """              <div className="flex items-center justify-between">
                <p className="text-ink">v{v.versionNumber} · {v.fileName}</p>
                {v.reviewed === false ? (
                  <span className="font-mono text-xs text-ink-faint">Filed — not reviewed</span>
                ) : (
                  <Link href={`/review/${contract.id}/${v.id}`} className="font-mono text-xs text-accent hover:underline">
                    View results
                  </Link>
                )}
              </div>"""
    new_version_row = """              <div className="flex items-center justify-between">
                <p className="text-ink">v{v.versionNumber} · {v.fileName}</p>
                <div className="flex items-center gap-3">
                  {v.reviewed === false ? (
                    <span className="font-mono text-xs text-ink-faint">Filed — not reviewed</span>
                  ) : (
                    <Link href={`/review/${contract.id}/${v.id}`} className="font-mono text-xs text-accent hover:underline">
                      View results
                    </Link>
                  )}
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      handleDeleteVersion(v.id, v.versionNumber);
                    }}
                    className="font-mono text-xs text-ink-faint hover:text-high"
                  >
                    Delete
                  </button>
                </div>
              </div>"""
    if old_version_row not in content:
        raise SystemExit("Expected version row not found in MatterCard.tsx — aborting.")
    content = content.replace(old_version_row, new_version_row)

    with open(path, "w") as f:
        f.write(content)
    print("MatterCard.tsx: added Delete for the whole contract and for individual versions.")
PYEOF

# ── 3. ClientDetailView.tsx — wire contract delete, rename Matters -> Contracts in visible text ──
python3 - << 'PYEOF'
path = "src/components/library/ClientDetailView.tsx"
with open(path) as f:
    content = f.read()

if "handleDeleteContract" in content:
    print("ClientDetailView.tsx: already present — nothing to do.")
else:
    old_handler_anchor = """  async function handleToggleMarkedReceived(contractId: string, value: boolean) {
    await setContractMarkedReceived(contractId, value);
    listContractsForClient(clientId).then(setContracts);
  }"""
    new_handler_anchor = """  async function handleToggleMarkedReceived(contractId: string, value: boolean) {
    await setContractMarkedReceived(contractId, value);
    listContractsForClient(clientId).then(setContracts);
  }

  async function handleDeleteContract(contractId: string) {
    await deleteContract(contractId);
    setContracts((prev) => prev.filter((c) => c.id !== contractId));
  }"""
    if old_handler_anchor not in content:
        raise SystemExit("Expected handleToggleMarkedReceived not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_handler_anchor, new_handler_anchor)

    old_import = """  createContract,
  addVersion,
  setContractMarkedReceived,
} from '@/lib/firebase/firestore';"""
    new_import = """  createContract,
  addVersion,
  setContractMarkedReceived,
  deleteContract,
} from '@/lib/firebase/firestore';"""
    if old_import not in content:
        raise SystemExit("Expected firestore import block not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_import, new_import)

    old_matters_map = """            <MatterCard
              contract={c}
              onEdit={() => setEditing(c)}
              isGoverningMsa={client.msaContractId === c.id}
              onToggleGoverningMsa={() => handleToggleGoverningMsa(c.id)}
              autoExpand={autoExpandMatterId === c.id}
              hasExecutedAgreement={executedAgreements.some((a) => a.contractId === c.id)}
              onToggleMarkedReceived={() => handleToggleMarkedReceived(c.id, !c.markedReceived)}
            />"""
    new_matters_map = """            <MatterCard
              contract={c}
              onEdit={() => setEditing(c)}
              onDelete={() => handleDeleteContract(c.id)}
              isGoverningMsa={client.msaContractId === c.id}
              onToggleGoverningMsa={() => handleToggleGoverningMsa(c.id)}
              autoExpand={autoExpandMatterId === c.id}
              hasExecutedAgreement={executedAgreements.some((a) => a.contractId === c.id)}
              onToggleMarkedReceived={() => handleToggleMarkedReceived(c.id, !c.markedReceived)}
            />"""
    if old_matters_map not in content:
        raise SystemExit("Expected Matters map not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_matters_map, new_matters_map)

    # Visible-label rename only — the data model already says "Contract"
    # everywhere under the hood (ContractDoc, contracts collection); it was
    # only ever the on-screen wording that said "Matter".
    renames = [
        ('{contracts.length} matters on file', '{contracts.length} contracts on file'),
        ('<p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">Matters</p>',
         '<p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">Contracts</p>'),
        ('No matters yet.', 'No contracts yet.'),
        ('<h3 className="font-display text-lg text-ink">Edit matter</h3>',
         '<h3 className="font-display text-lg text-ink">Edit contract</h3>'),
    ]
    missing = [old for old, _ in renames if old not in content]
    if missing:
        raise SystemExit(f"Expected label(s) not found in ClientDetailView.tsx: {missing} — aborting.")
    for old, new in renames:
        content = content.replace(old, new)

    with open(path, "w") as f:
        f.write(content)
    print("ClientDetailView.tsx: wired contract delete and renamed visible 'Matters' labels to 'Contracts'.")
PYEOF

# ── 4. ClientListView.tsx — list open contracts + inline "Mark received" on each card, rename label ──
python3 - << 'PYEOF'
path = "src/components/library/ClientListView.tsx"
with open(path) as f:
    content = f.read()

if "handleMarkReceived" in content:
    print("ClientListView.tsx: already present — nothing to do.")
else:
    old_import = "import { subscribeClients, getOrCreateClient, ensureClientDriveFolder } from '@/lib/firebase/firestore';"
    new_import = "import { subscribeClients, getOrCreateClient, ensureClientDriveFolder, setContractMarkedReceived } from '@/lib/firebase/firestore';"
    if old_import not in content:
        raise SystemExit("Expected firestore import not found in ClientListView.tsx — aborting.")
    content = content.replace(old_import, new_import)

    old_new_client_fn = """  async function handleNewClient() {"""
    new_new_client_fn = """  async function handleMarkReceived(clientId: string, contractId: string) {
    await setContractMarkedReceived(contractId, true);
    setContractsByClient((prev) => ({
      ...prev,
      [clientId]: (prev[clientId] ?? []).map((c) => (c.id === contractId ? { ...c, markedReceived: true } : c)),
    }));
  }

  async function handleNewClient() {"""
    if old_new_client_fn not in content:
        raise SystemExit("Expected handleNewClient not found in ClientListView.tsx — aborting.")
    content = content.replace(old_new_client_fn, new_new_client_fn)

    old_card = """        {filtered.map((client) => {
          const matters = contractsByClient[client.id] ?? [];
          const executed = executedByClient[client.id] ?? [];
          const executedContractIds = new Set(executed.map((e) => e.contractId).filter(Boolean));
          const openMatters = matters.filter((m) => !executedContractIds.has(m.id) && !m.markedReceived);
          const mostRecent = matters[0]?.createdAt;
          return (
            <Link key={client.id} href={`/library/${client.id}`}>
              <Card className="p-4 transition hover:border-ink">
                <p className="font-display text-lg text-ink">{client.name}</p>
                <p className="mt-1 font-mono text-xs text-ink-faint">
                  {matters.length} matter{matters.length === 1 ? '' : 's'}
                  {executed.length > 0 && ` · ${executed.length} executed`}
                  {matters.length > 0 && openMatters.length > 0 && ` · ${openMatters.length} open`}
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
        })}"""
    new_card = """        {filtered.map((client) => {
          const matters = contractsByClient[client.id] ?? [];
          const executed = executedByClient[client.id] ?? [];
          const executedContractIds = new Set(executed.map((e) => e.contractId).filter(Boolean));
          const openMatters = matters.filter((m) => !executedContractIds.has(m.id) && !m.markedReceived);
          const mostRecent = matters[0]?.createdAt;
          return (
            <Link key={client.id} href={`/library/${client.id}`}>
              <Card className="p-4 transition hover:border-ink">
                <p className="font-display text-lg text-ink">{client.name}</p>
                <p className="mt-1 font-mono text-xs text-ink-faint">
                  {matters.length} contract{matters.length === 1 ? '' : 's'}
                  {executed.length > 0 && ` · ${executed.length} executed`}
                  {matters.length > 0 && openMatters.length > 0 && ` · ${openMatters.length} open`}
                </p>
                <p className="mt-1 font-mono text-xs text-ink-faint">
                  {mostRecent ? `Last upload ${new Date(mostRecent).toLocaleDateString()}` : 'No uploads yet'}
                </p>
                {openMatters.length > 0 && (
                  <div className="mt-2 space-y-1 border-t border-rule pt-2">
                    {openMatters.slice(0, 3).map((m) => (
                      <div key={m.id} className="flex items-center justify-between gap-2">
                        <span className="truncate font-body text-xs text-ink-soft">
                          {m.projectName}{' '}
                          <span className="font-mono text-[10px] text-ink-faint">({m.projectNumber})</span>
                        </span>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.preventDefault();
                            e.stopPropagation();
                            handleMarkReceived(client.id, m.id);
                          }}
                          className="shrink-0 font-mono text-[10px] uppercase tracking-wide text-ink-faint hover:text-ink"
                        >
                          Mark received
                        </button>
                      </div>
                    ))}
                    {openMatters.length > 3 && (
                      <p className="font-mono text-[10px] text-ink-faint">+{openMatters.length - 3} more open</p>
                    )}
                  </div>
                )}
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
        })}"""
    if old_card not in content:
        raise SystemExit("Expected client card block not found in ClientListView.tsx — aborting.")
    content = content.replace(old_card, new_card)

    with open(path, "w") as f:
        f.write(content)
    print("ClientListView.tsx: cards now list open contracts inline with a one-click 'Mark received', and say 'contracts' not 'matters'.")
PYEOF

# ── 5. Small visible-label renames elsewhere ─────────────────────────────────
python3 - << 'PYEOF'
path = "src/app/dashboard/page.tsx"
with open(path) as f:
    content = f.read()
renames = [
    ('Total matters', 'Total contracts'),
    ('No reviewed matters yet.', 'No reviewed contracts yet.'),
]
changed = False
for old, new in renames:
    if old in content:
        content = content.replace(old, new)
        changed = True
if changed:
    with open(path, "w") as f:
        f.write(content)
    print("dashboard/page.tsx: renamed visible 'matters' labels to 'contracts'.")
else:
    print("dashboard/page.tsx: already renamed — nothing to do.")
PYEOF

python3 - << 'PYEOF'
path = "src/app/review/[contractId]/[versionId]/page.tsx"
with open(path) as f:
    content = f.read()
old = "of this matter is on file."
new = "of this contract is on file."
if old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("review/[contractId]/[versionId]/page.tsx: renamed 'this matter' to 'this contract'.")
else:
    print("review/[contractId]/[versionId]/page.tsx: already renamed — nothing to do.")
PYEOF

python3 - << 'PYEOF'
path = "src/components/review/ResultsView.tsx"
with open(path) as f:
    content = f.read()
old = "Waiting on the Drive upload to finish for this matter"
new = "Waiting on the Drive upload to finish for this contract"
if old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("ResultsView.tsx: renamed tooltip 'this matter' to 'this contract'.")
else:
    print("ResultsView.tsx: already renamed — nothing to do.")
PYEOF

echo ""
echo "Restart your dev server and check:"
echo "  1. Library grid — a client with open contracts should now list them"
echo "     by name right on the card (up to 3, then '+N more'), each with a"
echo "     'Mark received' link you can click WITHOUT opening the client."
echo "  2. Open a client — the section below is now labeled 'Contracts', not"
echo "     'Matters', and 'X contracts on file' at the top matches."
echo "  3. On a contract's card, 'Delete' next to Edit removes the whole"
echo "     contract (with a confirm prompt) — Drive files aren't touched."
echo "  4. Expand a contract's version history — each version now has its"
echo "     own 'Delete' link too, for removing just one bad upload."
echo ""
echo "Then npm run build, commit, and push (via GitHub Desktop) to deploy."
