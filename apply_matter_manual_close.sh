#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_matter_manual_close.sh
set -e

# ── 1. types.ts — ContractDoc gets a manual "received" flag ─────────────────
python3 - << 'PYEOF'
import re
path = "src/lib/types.ts"
with open(path) as f:
    content = f.read()

block = re.search(r"export interface ContractDoc \{[\s\S]*?\n\}", content)
if block and "markedReceived" in block.group(0):
    print("types.ts: already present — nothing to do.")
else:
    old = """  createdAt: number;
  latestVersionId: string | null;
}"""
    new = """  createdAt: number;
  latestVersionId: string | null;
  // Manually marks a matter as closed/received when there's no executed
  // file to upload (e.g. signed elsewhere, filed outside Drive). A matter
  // linked to a real executed agreement is closed automatically regardless
  // of this flag — this only matters for the no-file case. Optional/missing
  // means false, same convention as other flags added after launch.
  markedReceived?: boolean;
}"""
    if old not in content:
        raise SystemExit("Expected ContractDoc fields not found in types.ts — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("types.ts: added markedReceived to ContractDoc.")
PYEOF

# ── 2. firestore.ts — setter for the manual flag ─────────────────────────────
python3 - << 'PYEOF'
path = "src/lib/firebase/firestore.ts"
with open(path) as f:
    content = f.read()

if "setContractMarkedReceived" in content:
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

// Manual close/reopen for a matter with no executed file to upload — a
// matter with a real linked executed agreement is closed automatically and
// doesn't need this; this only covers the "signed elsewhere, nothing to
// upload" case.
export async function setContractMarkedReceived(contractId: string, markedReceived: boolean) {
  await updateDoc(doc(db, 'contracts', contractId), { markedReceived });
}"""
    if old not in content:
        raise SystemExit("Expected moveContract not found in firestore.ts — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("firestore.ts: added setContractMarkedReceived.")
PYEOF

# ── 3. MatterCard.tsx — closed badge + manual toggle ─────────────────────────
python3 - << 'PYEOF'
path = "src/components/library/MatterCard.tsx"
with open(path) as f:
    content = f.read()

if "hasExecutedAgreement" in content:
    print("MatterCard.tsx: already present — nothing to do.")
else:
    old_props = """export function MatterCard({
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
}) {"""
    new_props = """export function MatterCard({
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
    if old_props not in content:
        raise SystemExit("Expected MatterCard props not found in MatterCard.tsx — aborting.")
    content = content.replace(old_props, new_props)

    old_header = """        <div className="flex items-center gap-3">
          {onToggleGoverningMsa && contract.docType !== 'SOW' && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onToggleGoverningMsa();
              }}
              className="font-mono text-xs text-ink-faint hover:text-ink"
            >
              {isGoverningMsa ? 'Unset as MSA' : 'Set as governing MSA'}
            </button>
          )}
          {latestUnreviewed ? ("""
    new_header = """        <div className="flex items-center gap-3">
          {onToggleGoverningMsa && contract.docType !== 'SOW' && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onToggleGoverningMsa();
              }}
              className="font-mono text-xs text-ink-faint hover:text-ink"
            >
              {isGoverningMsa ? 'Unset as MSA' : 'Set as governing MSA'}
            </button>
          )}
          {hasExecutedAgreement ? (
            <span className="rounded-full border border-low/30 bg-low-bg px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide text-low">
              Executed
            </span>
          ) : contract.markedReceived ? (
            <span className="flex items-center gap-1.5">
              <span className="rounded-full border border-low/30 bg-low-bg px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide text-low">
                Marked received
              </span>
              {onToggleMarkedReceived && (
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onToggleMarkedReceived();
                  }}
                  className="font-mono text-xs text-ink-faint hover:text-ink"
                >
                  Undo
                </button>
              )}
            </span>
          ) : (
            onToggleMarkedReceived && (
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onToggleMarkedReceived();
                }}
                className="font-mono text-xs text-ink-faint hover:text-ink"
              >
                Mark as received
              </button>
            )
          )}
          {latestUnreviewed ? ("""
    if old_header not in content:
        raise SystemExit("Expected MatterCard header row not found in MatterCard.tsx — aborting.")
    content = content.replace(old_header, new_header)

    with open(path, "w") as f:
        f.write(content)
    print("MatterCard.tsx: added the closed/received badge and manual toggle.")
PYEOF

# ── 4. ClientDetailView.tsx — wire executed-agreement lookup + toggle handler into each MatterCard ──
python3 - << 'PYEOF'
path = "src/components/library/ClientDetailView.tsx"
with open(path) as f:
    content = f.read()

if "handleToggleMarkedReceived" in content:
    print("ClientDetailView.tsx: already present — nothing to do.")
else:
    old_import = """  createContract,
  addVersion,
} from '@/lib/firebase/firestore';"""
    new_import = """  createContract,
  addVersion,
  setContractMarkedReceived,
} from '@/lib/firebase/firestore';"""
    if old_import not in content:
        raise SystemExit("Expected firestore import block not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_import, new_import)

    old_handler_anchor = """  async function handleToggleGoverningMsa(contractId: string) {
    if (!client) return;
    if (client.msaContractId === contractId) {
      await clearGoverningMsa(clientId);
    } else {
      await setGoverningMsa(clientId, contractId);
    }
    getClient(clientId).then(setClient);
  }"""
    new_handler_anchor = """  async function handleToggleGoverningMsa(contractId: string) {
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
  }"""
    if old_handler_anchor not in content:
        raise SystemExit("Expected handleToggleGoverningMsa not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_handler_anchor, new_handler_anchor)

    old_matters_map = """        {contracts.map((c) => (
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
    new_matters_map = """        {contracts.map((c) => (
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
        ))}"""
    if old_matters_map not in content:
        raise SystemExit("Expected Matters map not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_matters_map, new_matters_map)

    with open(path, "w") as f:
        f.write(content)
    print("ClientDetailView.tsx: MatterCards now know whether they're closed and can toggle the manual flag.")
PYEOF

# ── 5. ClientListView.tsx — a manually-received matter also counts as closed, not open ──
python3 - << 'PYEOF'
path = "src/components/library/ClientListView.tsx"
with open(path) as f:
    content = f.read()

if "!m.markedReceived" in content:
    print("ClientListView.tsx: already present — nothing to do.")
else:
    old = "const openMatters = matters.filter((m) => !executedContractIds.has(m.id));"
    new = "const openMatters = matters.filter((m) => !executedContractIds.has(m.id) && !m.markedReceived);"
    if old not in content:
        raise SystemExit("Expected openMatters calc not found in ClientListView.tsx — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("ClientListView.tsx: manually-received matters no longer count toward 'open'.")
PYEOF

echo ""
echo "Restart your dev server and check a client with at least one matter"
echo "that has no executed agreement on file:"
echo "  1. That matter's card should show a 'Mark as received' link next to"
echo "     Edit. Click it — it should switch to a green 'Marked received'"
echo "     badge with an 'Undo' link."
echo "  2. Click Undo — it should go back to 'Mark as received'."
echo "  3. On the Library page, that client's '· N open' count should drop"
echo "     by one while marked received, and go back up after Undo."
echo "  4. A matter that already has a real executed agreement linked to it"
echo "     should show a plain 'Executed' badge instead, with no toggle —"
echo "     that one's closed via the real file, not the manual flag."
echo ""
echo "Then npm run build, commit, and push (via GitHub Desktop) to deploy."
