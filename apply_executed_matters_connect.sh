#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_executed_matters_connect.sh
set -e

# ── 1. types.ts — ExecutedAgreementDoc gets a real contractId link ──────────
python3 - << 'PYEOF'
import re
path = "src/lib/types.ts"
with open(path) as f:
    content = f.read()

block = re.search(r"export interface ExecutedAgreementDoc \{[\s\S]*?\n\}", content)
if block and "contractId" in block.group(0):
    print("types.ts: already present — nothing to do.")
else:
    old = """  // Which job this is filed under — required for SOW/Change Order (always
  // job-specific), null for MSA/Other left at the client level (an MSA
  // typically governs many jobs, not just one).
  projectNumber: string | null;
  projectName: string | null;"""
    new = """  // The matter (ContractDoc) this executed file is filed under — set
  // whenever a project is picked, creating a new matter first if the
  // project didn't have one yet. Null only for a client-level MSA/Other
  // filed with no project. This is what lets the Library and client page
  // actually connect an executed agreement to its matter instead of the
  // two just sitting next to each other as unrelated records.
  contractId: string | null;
  // Which job this is filed under — required for SOW/Change Order (always
  // job-specific), null for MSA/Other left at the client level (an MSA
  // typically governs many jobs, not just one).
  projectNumber: string | null;
  projectName: string | null;"""
    if old not in content:
        raise SystemExit("Expected ExecutedAgreementDoc fields not found in types.ts — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("types.ts: added contractId to ExecutedAgreementDoc.")
PYEOF

# ── 2. ClientDetailView.tsx — resolve/create the matter, link executed rows to it ──
python3 - << 'PYEOF'
path = "src/components/library/ClientDetailView.tsx"
with open(path) as f:
    content = f.read()

if "existingMatter" in content:
    print("ClientDetailView.tsx: already present — nothing to do.")
else:
    old_import = """import {
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
} from '@/lib/firebase/firestore';"""
    new_import = """import {
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
} from '@/lib/firebase/firestore';"""
    if old_import not in content:
        raise SystemExit("Expected firestore import block not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_import, new_import)

    old_handler = """  async function handleUploadAgreement(e: React.ChangeEvent<HTMLInputElement>) {
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
      await addExecutedAgreement(clientId, {
        docType: agreementDocType,
        label: agreementLabel.trim(),
        driveFileId: data.driveFileId,
        driveUrl: data.driveUrl,
        driveFolderUrl: data.driveFolderUrl ?? null,
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
  }"""
    new_handler = """  async function handleUploadAgreement(e: React.ChangeEvent<HTMLInputElement>) {
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
  }"""
    if old_handler not in content:
        raise SystemExit("Expected handleUploadAgreement not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_handler, new_handler)

    old_list_item = """                  {a.projectNumber && (
                    <span className="mr-2 font-mono text-[10px] text-ink-faint">
                      {a.projectNumber} — {a.projectName}
                    </span>
                  )}"""
    new_list_item = """                  {a.projectNumber && (
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
                  )}"""
    if old_list_item not in content:
        raise SystemExit("Expected executed-agreement list item not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_list_item, new_list_item)

    with open(path, "w") as f:
        f.write(content)
    print("ClientDetailView.tsx: executed agreements now create/attach to a real matter, and link to it.")
PYEOF

# ── 3. IntakeForm.tsx — "mark as executed" option on the main upload page ───
python3 - << 'PYEOF'
path = "src/components/intake/IntakeForm.tsx"
with open(path) as f:
    content = f.read()

if "markExecuted" in content:
    print("IntakeForm.tsx: already present — nothing to do.")
else:
    old_interface = """  /** When true, skips Claude analysis entirely — just files the contract to
   * Drive and tracks it as a matter for reference (e.g. an already-executed
   * contract, an amendment, an insurance cert). */
  skipReview: boolean;
}"""
    new_interface = """  /** When true, skips Claude analysis entirely — just files the contract to
   * Drive and tracks it as a matter for reference (e.g. an already-executed
   * contract, an amendment, an insurance cert). */
  skipReview: boolean;
  /** When true (only meaningful alongside skipReview), also records this as
   * an executed agreement on the client — same file, same Drive location —
   * so it shows up in that client's Executed Agreements list too. */
  markExecuted: boolean;
}"""
    if old_interface not in content:
        raise SystemExit("Expected IntakeValues interface not found in IntakeForm.tsx — aborting.")
    content = content.replace(old_interface, new_interface)

    old_state = """  const [skipReview, setSkipReview] = useState(true);"""
    new_state = """  const [skipReview, setSkipReview] = useState(true);
  const [markExecuted, setMarkExecuted] = useState(false);"""
    if old_state not in content:
        raise SystemExit("Expected skipReview state not found in IntakeForm.tsx — aborting.")
    content = content.replace(old_state, new_state)

    old_chip = """      <div className="mb-6 flex justify-center">
        <Chip>
          {user.displayName ?? user.email} · {user.email}
        </Chip>
      </div>"""
    new_chip = """      <div className="mb-6 flex justify-center">
        <Chip>
          {user.displayName ?? user.email} · {user.email}
        </Chip>
      </div>
      {skipReview && (
        <div className="mb-6 flex justify-center">
          <label className="flex items-center gap-1.5 font-mono text-xs text-ink-faint">
            <input
              type="checkbox"
              checked={markExecuted}
              onChange={(e) => setMarkExecuted(e.target.checked)}
            />
            This is a fully executed / signed copy — also file it under Executed Agreements for this client
          </label>
        </div>
      )}"""
    if old_chip not in content:
        raise SystemExit("Expected Chip block not found in IntakeForm.tsx — aborting.")
    content = content.replace(old_chip, new_chip)

    old_submit = """            onSubmit({
              clientName: clientName.trim(),
              projectName: projectName.trim(),
              projectNumber: projectNumber.trim(),
              docType,
              counterparty: counterparty.trim(),
              file,
              documentText,
              characterCount: characterCount ?? 0,
              existingContractId: selectedContractId ?? undefined,
              skipReview,
            })
          }
        >
          {submitting ? (skipReview ? 'Filing…' : 'Running review…') : skipReview ? 'File for reference' : 'Run Review'}"""
    new_submit = """            onSubmit({
              clientName: clientName.trim(),
              projectName: projectName.trim(),
              projectNumber: projectNumber.trim(),
              docType,
              counterparty: counterparty.trim(),
              file,
              documentText,
              characterCount: characterCount ?? 0,
              existingContractId: selectedContractId ?? undefined,
              skipReview,
              markExecuted: skipReview && markExecuted,
            })
          }
        >
          {submitting
            ? skipReview
              ? markExecuted
                ? 'Filing as executed…'
                : 'Filing…'
              : 'Running review…'
            : skipReview
              ? markExecuted
                ? 'File as executed'
                : 'File for reference'
              : 'Run Review'}"""
    if old_submit not in content:
        raise SystemExit("Expected submit button block not found in IntakeForm.tsx — aborting.")
    content = content.replace(old_submit, new_submit)

    with open(path, "w") as f:
        f.write(content)
    print("IntakeForm.tsx: added the 'mark as executed' option to file-for-reference mode.")
PYEOF

# ── 4. page.tsx — record the executed agreement using the file just uploaded ──
python3 - << 'PYEOF'
path = "src/app/page.tsx"
with open(path) as f:
    content = f.read()

if "markExecuted" in content:
    print("page.tsx: already present — nothing to do.")
else:
    old_import = """import {
  getOrCreateClient,
  createContract,
  addVersion,
  updateContractDrive,
  updateVersionDrive,
  getClient,
  getNextVersionNumber,
  listVersionsForContract,
} from '@/lib/firebase/firestore';"""
    new_import = """import {
  getOrCreateClient,
  createContract,
  addVersion,
  updateContractDrive,
  updateVersionDrive,
  getClient,
  getNextVersionNumber,
  listVersionsForContract,
  addExecutedAgreement,
} from '@/lib/firebase/firestore';"""
    if old_import not in content:
        raise SystemExit("Expected firestore import block not found in page.tsx — aborting.")
    content = content.replace(old_import, new_import)

    old_drive_vars = """      let driveFileId: string | null = null;
      let driveFolderId: string | null = null;
      let driveFolderUrl: string | null = null;
      try {
        const form = new FormData();
        form.append('file', values.file);
        form.append('clientName', client.name);
        form.append('projectName', values.projectName);
        form.append('projectNumber', values.projectNumber);
        form.append('docType', values.docType);
        if (versionNumber > 1) form.append('versionSuffix', `v${versionNumber}`);
        const driveRes = await fetch('/api/drive/upload', { method: 'POST', body: form });
        const driveData = await driveRes.json();
        if (!driveData.error) {
          await updateContractDrive(contractId, driveData);
          await updateVersionDrive(contractId, versionId, {
            driveFileId: driveData.driveFileId ?? null,
            driveUrl: driveData.driveUrl ?? null,
            driveFolderId: driveData.driveFolderId ?? null,
            driveFolderUrl: driveData.driveFolderUrl ?? null,
          });
          driveFileId = driveData.driveFileId ?? null;
          driveFolderId = driveData.driveFolderId ?? null;
          driveFolderUrl = driveData.driveFolderUrl ?? null;
        }
      } catch {
        // Drive failures shouldn't block the reviewer from seeing results.
      }"""
    new_drive_vars = """      let driveFileId: string | null = null;
      let driveUrl: string | null = null;
      let driveFolderId: string | null = null;
      let driveFolderUrl: string | null = null;
      try {
        const form = new FormData();
        form.append('file', values.file);
        form.append('clientName', client.name);
        form.append('projectName', values.projectName);
        form.append('projectNumber', values.projectNumber);
        form.append('docType', values.docType);
        if (versionNumber > 1) form.append('versionSuffix', `v${versionNumber}`);
        const driveRes = await fetch('/api/drive/upload', { method: 'POST', body: form });
        const driveData = await driveRes.json();
        if (!driveData.error) {
          await updateContractDrive(contractId, driveData);
          await updateVersionDrive(contractId, versionId, {
            driveFileId: driveData.driveFileId ?? null,
            driveUrl: driveData.driveUrl ?? null,
            driveFolderId: driveData.driveFolderId ?? null,
            driveFolderUrl: driveData.driveFolderUrl ?? null,
          });
          driveFileId = driveData.driveFileId ?? null;
          driveUrl = driveData.driveUrl ?? null;
          driveFolderId = driveData.driveFolderId ?? null;
          driveFolderUrl = driveData.driveFolderUrl ?? null;
        }
      } catch {
        // Drive failures shouldn't block the reviewer from seeing results.
      }

      // Flagged as a fully executed/signed copy — record it as an executed
      // agreement on the client too, reusing the SAME Drive file/location
      // just uploaded above rather than uploading a second copy through the
      // separate executed-agreement route. Non-fatal: a failure here
      // shouldn't block filing from completing.
      if (values.markExecuted && values.skipReview && driveFileId) {
        try {
          await addExecutedAgreement(client.id, {
            docType: values.docType,
            label: '',
            driveFileId,
            driveUrl: driveUrl ?? '',
            driveFolderUrl,
            contractId,
            projectNumber: values.projectNumber,
            projectName: values.projectName,
            executedDate: null,
            uploadedBy: { name: user!.displayName ?? user!.email ?? '', email: user!.email ?? '' },
          });
        } catch {
          // Non-fatal — the matter/version itself already filed successfully.
        }
      }"""
    if old_drive_vars not in content:
        raise SystemExit("Expected Drive upload block not found in page.tsx — aborting.")
    content = content.replace(old_drive_vars, new_drive_vars)

    old_filed_msg = """        <p className="mt-3 font-body text-sm text-ink-soft">
          {filedInfo.projectName} ({filedInfo.projectNumber}) was saved to Drive and filed under{' '}
          {filedInfo.clientName} — no Claude review was run.
        </p>"""
    new_filed_msg = """        <p className="mt-3 font-body text-sm text-ink-soft">
          {filedInfo.projectName} ({filedInfo.projectNumber}) was saved to Drive and filed under{' '}
          {filedInfo.clientName} — no Claude review was run.
          {filedInfo.markExecuted ? ' Also added to this client\\'s Executed Agreements.' : ''}
        </p>"""
    if old_filed_msg not in content:
        raise SystemExit("Expected filed-info message not found in page.tsx — aborting.")
    content = content.replace(old_filed_msg, new_filed_msg)

    old_filed_state = """  const [filedInfo, setFiledInfo] = useState<{
    clientId: string;
    clientName: string;
    projectName: string;
    projectNumber: string;
    driveFolderUrl: string | null;
  } | null>(null);"""
    new_filed_state = """  const [filedInfo, setFiledInfo] = useState<{
    clientId: string;
    clientName: string;
    projectName: string;
    projectNumber: string;
    driveFolderUrl: string | null;
    markExecuted: boolean;
  } | null>(null);"""
    if old_filed_state not in content:
        raise SystemExit("Expected filedInfo state not found in page.tsx — aborting.")
    content = content.replace(old_filed_state, new_filed_state)

    old_set_filed = """        setFiledInfo({
          clientId: client.id,
          clientName: client.name,
          projectName: values.projectName,
          projectNumber: values.projectNumber,
          driveFolderUrl,
        });"""
    new_set_filed = """        setFiledInfo({
          clientId: client.id,
          clientName: client.name,
          projectName: values.projectName,
          projectNumber: values.projectNumber,
          driveFolderUrl,
          markExecuted: values.markExecuted && values.skipReview,
        });"""
    if old_set_filed not in content:
        raise SystemExit("Expected setFiledInfo call not found in page.tsx — aborting.")
    content = content.replace(old_set_filed, new_set_filed)

    with open(path, "w") as f:
        f.write(content)
    print("page.tsx: filing as executed now also creates the executed-agreement record.")
PYEOF

# ── 5. ClientListView.tsx — show executed/open counts on each client card ───
python3 - << 'PYEOF'
path = "src/components/library/ClientListView.tsx"
with open(path) as f:
    content = f.read()

if "executedByClient" in content:
    print("ClientListView.tsx: already present — nothing to do.")
else:
    old_import_types = "import type { ClientDoc, ContractDoc } from '@/lib/types';"
    new_import_types = "import type { ClientDoc, ContractDoc, ExecutedAgreementDoc } from '@/lib/types';"
    if old_import_types not in content:
        raise SystemExit("Expected types import not found in ClientListView.tsx — aborting.")
    content = content.replace(old_import_types, new_import_types)

    old_state = "  const [contractsByClient, setContractsByClient] = useState<Record<string, ContractDoc[]>>({});"
    new_state = """  const [contractsByClient, setContractsByClient] = useState<Record<string, ContractDoc[]>>({});
  const [executedByClient, setExecutedByClient] = useState<Record<string, ExecutedAgreementDoc[]>>({});"""
    if old_state not in content:
        raise SystemExit("Expected contractsByClient state not found in ClientListView.tsx — aborting.")
    content = content.replace(old_state, new_state)

    old_effect_end = """      setContractsByClient(grouped);
    })().catch(() => {});
  }, []);"""
    new_effect_end = """      setContractsByClient(grouped);
    })().catch(() => {});
  }, []);

  // Same one-shot fetch-and-group approach as contracts above, but via a
  // collectionGroup query since executed agreements live in a per-client
  // subcollection (clients/{clientId}/executedAgreements) rather than a
  // top-level one — the client id comes off each doc's own path
  // (ref.parent.parent), not a stored field.
  useEffect(() => {
    (async () => {
      const { collectionGroup, getDocs: gd } = await import('firebase/firestore');
      const snap = await gd(collectionGroup(db, 'executedAgreements'));
      const grouped: Record<string, ExecutedAgreementDoc[]> = {};
      snap.docs.forEach((d) => {
        const clientId = d.ref.parent.parent?.id;
        if (!clientId) return;
        const data = d.data() as Omit<ExecutedAgreementDoc, 'id'>;
        grouped[clientId] = grouped[clientId] || [];
        grouped[clientId].push({ id: d.id, ...data });
      });
      setExecutedByClient(grouped);
    })().catch(() => {});
  }, []);"""
    if old_effect_end not in content:
        raise SystemExit("Expected contracts-fetch effect not found in ClientListView.tsx — aborting.")
    content = content.replace(old_effect_end, new_effect_end)

    old_card = """        {filtered.map((client) => {
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
                </p>"""
    new_card = """        {filtered.map((client) => {
          const matters = contractsByClient[client.id] ?? [];
          const executed = executedByClient[client.id] ?? [];
          const executedContractIds = new Set(executed.map((e) => e.contractId).filter(Boolean));
          const openMatters = matters.filter((m) => !executedContractIds.has(m.id));
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
                </p>"""
    if old_card not in content:
        raise SystemExit("Expected client card block not found in ClientListView.tsx — aborting.")
    content = content.replace(old_card, new_card)

    with open(path, "w") as f:
        f.write(content)
    print("ClientListView.tsx: client cards now show executed/open counts.")
PYEOF

echo ""
echo "Restart your dev server and check:"
echo "  1. Client page — Executed Agreements: pick '+ New project…', upload"
echo "     a file. That project should now also appear under 'Matters'"
echo "     below, and 'X matters on file' at the top should count it."
echo "  2. Same panel, existing entries with a project — the project text is"
echo "     now a link that jumps down to that matter's card."
echo "  3. Library — client cards should now show '· N executed' and, for"
echo "     any client with a matter that has no matching executed agreement,"
echo "     '· N open'."
echo "  4. Main upload page ('+ Upload contract') — switch to 'File for"
echo "     reference (no review)', check 'This is a fully executed / signed"
echo "     copy', submit. Confirm it shows up in that client's Executed"
echo "     Agreements list afterward, not just Matters."
echo ""
echo "One thing this does NOT fix retroactively: the two executed agreements"
echo "already on file for Said Differently (Niagen VS26149, DXC VS26148)"
echo "were created before contractId existed, so they'll keep showing as"
echo "disconnected — they'll still count toward the client's total 'executed'"
echo "number, just not toward closing out a specific matter. Easiest fix for"
echo "those two specifically: remove them from the list and re-upload the"
echo "same files (already safe in Drive) so they get created with a proper"
echo "matter link."
echo ""
echo "Then npm run build, commit, and push (via GitHub Desktop) to deploy."
