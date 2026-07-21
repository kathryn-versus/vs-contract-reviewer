#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_reconnect_executed_agreements.sh
set -e

# ── 1. firestore.ts — setter to point an executed agreement at a contract ──
python3 - << 'PYEOF'
path = "src/lib/firebase/firestore.ts"
with open(path) as f:
    content = f.read()

if "export async function setExecutedAgreementContract" in content:
    print("firestore.ts: already present — nothing to do.")
else:
    old = """export async function deleteExecutedAgreement(clientId: string, agreementId: string): Promise<void> {
  await deleteDoc(doc(db, 'clients', clientId, 'executedAgreements', agreementId));
}"""
    new = """export async function deleteExecutedAgreement(clientId: string, agreementId: string): Promise<void> {
  await deleteDoc(doc(db, 'clients', clientId, 'executedAgreements', agreementId));
}

// Points an executed agreement at a contract after the fact — used by the
// "Reconnect" repair action on the client page for agreements uploaded
// before contract-linking existed (or whose linked contract was deleted).
export async function setExecutedAgreementContract(
  clientId: string,
  agreementId: string,
  contractId: string
): Promise<void> {
  await updateDoc(doc(db, 'clients', clientId, 'executedAgreements', agreementId), { contractId });
}"""
    if old not in content:
        raise SystemExit("Expected deleteExecutedAgreement not found in firestore.ts — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("firestore.ts: added setExecutedAgreementContract.")
PYEOF

# ── 2. ClientDetailView.tsx — detect orphaned executed agreements + a one-click Reconnect action ──
python3 - << 'PYEOF'
path = "src/components/library/ClientDetailView.tsx"
with open(path) as f:
    content = f.read()

if "handleReconnectAgreements" in content:
    print("ClientDetailView.tsx: already present — nothing to do.")
else:
    old_import = """  setContractMarkedReceived,
  deleteContract,
} from '@/lib/firebase/firestore';"""
    new_import = """  setContractMarkedReceived,
  deleteContract,
  setExecutedAgreementContract,
} from '@/lib/firebase/firestore';"""
    if old_import not in content:
        raise SystemExit("Expected firestore import block not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_import, new_import)

    old_state = """  const [uploadingAgreement, setUploadingAgreement] = useState(false);
  const [agreementError, setAgreementError] = useState<string | null>(null);
  const { user } = useAuth();"""
    new_state = """  const [uploadingAgreement, setUploadingAgreement] = useState(false);
  const [agreementError, setAgreementError] = useState<string | null>(null);
  const [reconnecting, setReconnecting] = useState(false);
  const { user } = useAuth();"""
    if old_state not in content:
        raise SystemExit("Expected agreementError state not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_state, new_state)

    old_resolve = """  function resolveAgreementProject(): { projectNumber: string; projectName: string } | null {
    if (agreementProjectKey === '__new__') {
      const projectNumber = agreementNewProjectNumber.trim();
      const projectName = agreementNewProjectName.trim();
      if (!projectNumber || !projectName) return null;
      return { projectNumber, projectName };
    }
    return projectOptions.find((p) => projectOptionKey(p.projectNumber, p.projectName) === agreementProjectKey) ?? null;
  }

  async function saveNotes() {"""
    new_resolve = """  function resolveAgreementProject(): { projectNumber: string; projectName: string } | null {
    if (agreementProjectKey === '__new__') {
      const projectNumber = agreementNewProjectNumber.trim();
      const projectName = agreementNewProjectName.trim();
      if (!projectNumber || !projectName) return null;
      return { projectNumber, projectName };
    }
    return projectOptions.find((p) => projectOptionKey(p.projectNumber, p.projectName) === agreementProjectKey) ?? null;
  }

  // Executed agreements that have a project but aren't actually linked to a
  // real contract — either uploaded before contract-linking existed, or
  // pointing at a contract that's since been deleted. "Reconnect" finds or
  // creates the matching contract for each of these.
  const orphanedAgreements = executedAgreements.filter(
    (a) => a.projectNumber && (!a.contractId || !contracts.some((c) => c.id === a.contractId))
  );

  async function saveNotes() {"""
    if old_resolve not in content:
        raise SystemExit("Expected resolveAgreementProject not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_resolve, new_resolve)

    old_delete_agreement = """  async function handleDeleteAgreement(agreementId: string) {
    await deleteExecutedAgreement(clientId, agreementId);
    setExecutedAgreements((prev) => prev.filter((a) => a.id !== agreementId));
  }

  return ("""
    new_delete_agreement = """  async function handleDeleteAgreement(agreementId: string) {
    await deleteExecutedAgreement(clientId, agreementId);
    setExecutedAgreements((prev) => prev.filter((a) => a.id !== agreementId));
  }

  async function handleReconnectAgreements() {
    if (!client || orphanedAgreements.length === 0) return;
    setReconnecting(true);
    try {
      let liveContracts = await listContractsForClient(clientId);
      for (const a of orphanedAgreements) {
        if (!a.projectNumber || !a.projectName) continue;
        let match = liveContracts.find(
          (c) => c.projectNumber === a.projectNumber && c.projectName === a.projectName
        );
        if (!match) {
          const newContractId = await createContract({
            clientId,
            clientName: client.name,
            projectName: a.projectName,
            projectNumber: a.projectNumber,
            docType: a.docType,
            counterparty: client.name,
            submittedBy: {
              uid: user?.uid ?? '',
              name: user?.displayName ?? user?.email ?? '',
              email: user?.email ?? '',
            },
            driveFileId: a.driveFileId ?? null,
            driveUrl: a.driveUrl ?? null,
            driveFolderUrl: a.driveFolderUrl ?? null,
            driveFolderId: null,
          });
          await addVersion(newContractId, {
            versionNumber: 1,
            uploadedBy: a.uploadedBy,
            fileName: a.label || a.docType,
            characterCount: 0,
            findings: [],
            insuranceRequirements: [],
            resolvedFindings: [],
            deltaFromPrevious: null,
            reviewed: false,
            driveFileId: a.driveFileId ?? null,
            driveUrl: a.driveUrl ?? null,
            driveFolderId: null,
            driveFolderUrl: a.driveFolderUrl ?? null,
            googleDocId: null,
            googleDocUrl: null,
            reportHtmlUrl: null,
            reportPdfUrl: null,
          });
          liveContracts = await listContractsForClient(clientId);
          match = liveContracts.find((c) => c.id === newContractId);
        }
        if (match) {
          await setExecutedAgreementContract(clientId, a.id, match.id);
        }
      }
      const [refreshedContracts, refreshedAgreements] = await Promise.all([
        listContractsForClient(clientId),
        listExecutedAgreements(clientId),
      ]);
      setContracts(refreshedContracts);
      setExecutedAgreements(refreshedAgreements);
    } finally {
      setReconnecting(false);
    }
  }

  return ("""
    if old_delete_agreement not in content:
        raise SystemExit("Expected handleDeleteAgreement not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_delete_agreement, new_delete_agreement)

    old_panel_header = """      <Card className="p-5">
        <p className="mb-3 font-mono text-[11px] uppercase tracking-wide text-ink-faint">Executed agreements</p>
        {executedAgreements.length > 0 && ("""
    new_panel_header = """      <Card className="p-5">
        <p className="mb-3 font-mono text-[11px] uppercase tracking-wide text-ink-faint">Executed agreements</p>
        {orphanedAgreements.length > 0 && (
          <div className="mb-4 flex items-center justify-between gap-3 rounded-sm border border-med/30 bg-med-bg p-3">
            <p className="font-body text-xs text-ink-soft">
              {orphanedAgreements.length} executed agreement{orphanedAgreements.length === 1 ? '' : 's'} on file{' '}
              {orphanedAgreements.length === 1 ? "isn't" : "aren't"} linked to a contract yet — this can happen for
              files uploaded before contract-linking existed.
            </p>
            <button
              type="button"
              onClick={handleReconnectAgreements}
              disabled={reconnecting}
              className="shrink-0 font-mono text-xs uppercase tracking-wide text-accent hover:underline disabled:opacity-50"
            >
              {reconnecting ? 'Reconnecting…' : 'Reconnect now'}
            </button>
          </div>
        )}
        {executedAgreements.length > 0 && ("""
    if old_panel_header not in content:
        raise SystemExit("Expected Executed agreements panel header not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_panel_header, new_panel_header)

    with open(path, "w") as f:
        f.write(content)
    print("ClientDetailView.tsx: added orphaned-agreement detection and the 'Reconnect now' repair action.")
PYEOF

echo ""
echo "Restart your dev server and open Said Differently's client page:"
echo "  1. You should see an amber banner above the Executed agreements list"
echo "     saying some agreements aren't linked to a contract, with a"
echo "     'Reconnect now' button."
echo "  2. Click it. It finds (or creates) the matching contract for each"
echo "     orphaned agreement and links them — no re-uploading needed."
echo "  3. The banner should disappear, and 'X contracts on file' at the top"
echo "     plus the Contracts list below should now include them."
echo "  4. This same button will show up for any client with the same"
echo "     issue, not just this one."
echo ""
echo "Then npm run build, commit, and push (via GitHub Desktop) to deploy."
