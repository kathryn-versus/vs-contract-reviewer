#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_executed_agreements.sh
set -e

# ── 1. types.ts — widen DocType, add ExecutedAgreementDoc ──────────────────
python3 - << 'PYEOF'
path = "src/lib/types.ts"
with open(path) as f:
    content = f.read()

if "ExecutedAgreementDoc" in content:
    print("types.ts: already present — nothing to do.")
else:
    old = "export type DocType = 'MSA' | 'SOW' | 'MSA+SOW' | 'Other';"
    new = """export type DocType = 'MSA' | 'SOW' | 'MSA+SOW' | 'Change Order' | 'Other';

export interface ExecutedAgreementDoc {
  id: string;
  docType: DocType;
  // Free-text description, e.g. "Change Order #2 — Additional Deliverables"
  // — optional since a single MSA/SOW often doesn't need one.
  label: string;
  driveFileId: string;
  driveUrl: string;
  executedDate: string | null;
  uploadedAt: number;
  uploadedBy: { name: string; email: string };
}"""
    if old not in content:
        raise SystemExit("Expected DocType line not found in types.ts — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("types.ts: added 'Change Order' to DocType and the ExecutedAgreementDoc type.")
PYEOF

# ── 2. firestore.rules — allow read (signed-in) / write (admin) on the new subcollection ──
python3 - << 'PYEOF'
path = "firestore.rules"
with open(path) as f:
    content = f.read()

if "executedAgreements" in content:
    print("firestore.rules: already present — nothing to do.")
else:
    old = """    match /clients/{clientId} {
      allow read: if isSignedIn();
      allow write: if isAdmin();
    }"""
    new = """    match /clients/{clientId} {
      allow read: if isSignedIn();
      allow write: if isAdmin();

      match /executedAgreements/{agreementId} {
        allow read: if isSignedIn();
        allow write: if isAdmin();
      }
    }"""
    if old not in content:
        raise SystemExit("Expected clients match block not found in firestore.rules — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("firestore.rules: added the executedAgreements subcollection rule.")
PYEOF

# ── 3. firestore.ts — CRUD for executed agreements ──────────────────────────
python3 - << 'PYEOF'
import re
path = "src/lib/firebase/firestore.ts"
with open(path) as f:
    content = f.read()

if "listExecutedAgreements" in content:
    print("firestore.ts: already present — nothing to do.")
else:
    import_pattern = re.compile(r"import\s*\{[\s\S]*?\}\s*from\s*'firebase/firestore';")
    m = import_pattern.search(content)
    if not m:
        raise SystemExit("Could not find the firebase/firestore import block — aborting.")
    import_block = m.group(0)
    if "deleteDoc" not in import_block:
        new_import_block = import_block.replace("{", "{ deleteDoc,", 1)
        content = content.replace(import_block, new_import_block)

    # Append the new functions at the end of the file.
    content = content.rstrip() + """

export async function listExecutedAgreements(clientId: string): Promise<ExecutedAgreementDoc[]> {
  const snap = await getDocs(
    query(collection(db, 'clients', clientId, 'executedAgreements'), orderBy('uploadedAt', 'desc'))
  );
  return snap.docs.map((d) => ({
    id: d.id,
    ...(d.data() as Omit<ExecutedAgreementDoc, 'id'>),
    uploadedAt: toMillis(d.data().uploadedAt),
  }));
}

export async function addExecutedAgreement(
  clientId: string,
  input: Omit<ExecutedAgreementDoc, 'id' | 'uploadedAt'>
): Promise<string> {
  const ref = await addDoc(collection(db, 'clients', clientId, 'executedAgreements'), {
    ...input,
    uploadedAt: serverTimestamp(),
  });
  return ref.id;
}

export async function deleteExecutedAgreement(clientId: string, agreementId: string): Promise<void> {
  await deleteDoc(doc(db, 'clients', clientId, 'executedAgreements', agreementId));
}
"""
    with open(path, "w") as f:
        f.write(content)
    print("firestore.ts: added listExecutedAgreements/addExecutedAgreement/deleteExecutedAgreement.")

# ExecutedAgreementDoc needs to be an imported type here — check/add it to
# whatever '@/lib/types' import already exists in this file.
with open(path) as f:
    content = f.read()
types_import_pattern = re.compile(r"import\s+(?:type\s+)?\{[\s\S]*?\}\s*from\s*'\./types'|import\s+(?:type\s+)?\{[\s\S]*?\}\s*from\s*'@/lib/types';")
tm = types_import_pattern.search(content)
if tm and "ExecutedAgreementDoc" not in tm.group(0):
    block = tm.group(0)
    new_block = block.replace("{", "{ ExecutedAgreementDoc,", 1)
    content = content.replace(block, new_block)
    with open(path, "w") as f:
        f.write(content)
    print("firestore.ts: added ExecutedAgreementDoc to the types import.")
elif not tm:
    print("WARNING: could not find a '@/lib/types' import in firestore.ts to add ExecutedAgreementDoc to — check this manually, TypeScript will flag it clearly if missing.")
PYEOF

# ── 4. New Drive upload route for executed agreements ───────────────────────
mkdir -p src/app/api/drive/upload-executed-agreement
if [ -f src/app/api/drive/upload-executed-agreement/route.ts ]; then
  echo "upload-executed-agreement route: already exists — nothing to do."
else
  cat > src/app/api/drive/upload-executed-agreement/route.ts << 'EOF'
import { NextRequest, NextResponse } from 'next/server';
import { ensureClientFolder, uploadFileToFolder } from '@/lib/drive/client';

// Uploads a fully executed/signed agreement straight to the client's Drive
// folder, labeled by document type — separate from the review pipeline's
// versions, since an executed copy (often countersigned externally, after
// negotiation) doesn't correspond to any single reviewed draft. Multiple can
// exist per client (e.g. an MSA plus several Change Orders over time).
export async function POST(req: NextRequest) {
  try {
    const form = await req.formData();
    const file = form.get('file') as File | null;
    const clientName = form.get('clientName') as string | null;
    const docType = form.get('docType') as string | null;
    const label = (form.get('label') as string | null) ?? '';

    if (!file || !clientName || !docType) {
      return NextResponse.json({ error: 'file, clientName, and docType are required.' }, { status: 400 });
    }

    const { folderId } = await ensureClientFolder(clientName);
    const buffer = Buffer.from(await file.arrayBuffer());

    const namePrefix = label ? `${docType} — ${label}` : docType;
    const { fileId, webViewLink } = await uploadFileToFolder({
      folderId,
      fileName: `Executed — ${namePrefix} — ${file.name}`,
      mimeType: file.type || 'application/octet-stream',
      buffer,
    });

    return NextResponse.json({ driveFileId: fileId, driveUrl: webViewLink });
  } catch (err) {
    console.error('drive/upload-executed-agreement failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Upload failed.' },
      { status: 500 }
    );
  }
}
EOF
  echo "Wrote src/app/api/drive/upload-executed-agreement/route.ts"
fi

# ── 5. ClientDetailView.tsx — the actual UI section ─────────────────────────
python3 - << 'PYEOF'
path = "src/components/library/ClientDetailView.tsx"
with open(path) as f:
    content = f.read()

if "Executed agreements" in content:
    print("ClientDetailView.tsx: already present — nothing to do.")
else:
    old_import_firestore = """import {
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
} from '@/lib/firebase/firestore';"""
    new_import_firestore = """import {
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

    old_import_recents = """import { recordRecentClient } from '@/lib/recents';
import type { ClientDoc, ContractDoc } from '@/lib/types';"""
    new_import_recents = """import { recordRecentClient } from '@/lib/recents';
import { useAuth } from '@/hooks/useAuth';
import type { ClientDoc, ContractDoc, DocType, ExecutedAgreementDoc } from '@/lib/types';"""

    old_state = """  const [uploadingMsa, setUploadingMsa] = useState(false);
  const [msaError, setMsaError] = useState<string | null>(null);"""
    new_state = """  const [uploadingMsa, setUploadingMsa] = useState(false);
  const [msaError, setMsaError] = useState<string | null>(null);
  const [executedAgreements, setExecutedAgreements] = useState<ExecutedAgreementDoc[]>([]);
  const [agreementDocType, setAgreementDocType] = useState<DocType>('SOW');
  const [agreementLabel, setAgreementLabel] = useState('');
  const [uploadingAgreement, setUploadingAgreement] = useState(false);
  const [agreementError, setAgreementError] = useState<string | null>(null);
  const { user } = useAuth();"""

    old_effect = """    listContractsForClient(clientId).then(setContracts);
    listClients().then(setAllClients);
    recordRecentClient(clientId);"""
    new_effect = """    listContractsForClient(clientId).then(setContracts);
    listClients().then(setAllClients);
    listExecutedAgreements(clientId).then(setExecutedAgreements);
    recordRecentClient(clientId);"""

    old_handlers_anchor = """  async function handleSetNoMsa(value: boolean) {
    if (!client) return;
    await setClientNoMsa(clientId, value);
    getClient(clientId).then(setClient);
  }"""
    new_handlers_anchor = """  async function handleSetNoMsa(value: boolean) {
    if (!client) return;
    await setClientNoMsa(clientId, value);
    getClient(clientId).then(setClient);
  }

  async function handleUploadAgreement(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file || !client) return;
    setUploadingAgreement(true);
    setAgreementError(null);
    try {
      const form = new FormData();
      form.append('file', file);
      form.append('clientName', client.name);
      form.append('docType', agreementDocType);
      form.append('label', agreementLabel);
      const res = await fetch('/api/drive/upload-executed-agreement', { method: 'POST', body: form });
      const data = await res.json();
      if (data.error) throw new Error(data.error);
      await addExecutedAgreement(clientId, {
        docType: agreementDocType,
        label: agreementLabel.trim(),
        driveFileId: data.driveFileId,
        driveUrl: data.driveUrl,
        executedDate: null,
        uploadedBy: { name: user?.displayName ?? user?.email ?? '', email: user?.email ?? '' },
      });
      setAgreementLabel('');
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
  }"""

    old_jsx_anchor = """      </Card>

      <div className="space-y-3">
        <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">Matters</p>"""
    new_jsx_anchor = """      </Card>

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
                  <a
                    href={a.driveUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="font-body text-sm text-accent hover:underline"
                  >
                    {a.label || a.docType} ↗
                  </a>
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
        <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">Matters</p>"""

    missing = [
        l for l, n in [
            ("firestore import", old_import_firestore),
            ("recents/type import", old_import_recents),
            ("state", old_state),
            ("effect", old_effect),
            ("handlers anchor", old_handlers_anchor),
            ("jsx anchor", old_jsx_anchor),
        ] if n not in content
    ]
    if missing:
        raise SystemExit(f"Expected block(s) not found in ClientDetailView.tsx: {missing} — aborting.")

    content = (
        content.replace(old_import_firestore, new_import_firestore)
        .replace(old_import_recents, new_import_recents)
        .replace(old_state, new_state)
        .replace(old_effect, new_effect)
        .replace(old_handlers_anchor, new_handlers_anchor)
        .replace(old_jsx_anchor, new_jsx_anchor)
    )
    with open(path, "w") as f:
        f.write(content)
    print("ClientDetailView.tsx: added the Executed Agreements section.")
PYEOF

# ── 6. IntakeForm.tsx — offer 'Change Order' in the normal review flow too (best-effort) ──
python3 - << 'PYEOF'
import re
path = "src/components/intake/IntakeForm.tsx"
with open(path) as f:
    content = f.read()

if "Change Order" in content:
    print("IntakeForm.tsx: 'Change Order' already offered — nothing to do.")
else:
    m = re.search(r"const DOC_TYPES[\s\S]*?;", content)
    if not m or "'Other'" not in m.group(0):
        print("NOTE: could not safely locate DOC_TYPES in IntakeForm.tsx — skipping this step (not required for")
        print("      the Executed Agreements feature itself). Add 'Change Order' to its options by hand if wanted.")
    else:
        block = m.group(0)
        new_block = block.replace("'Other'", "'Change Order', 'Other'", 1)
        content = content.replace(block, new_block)
        with open(path, "w") as f:
            f.write(content)
        print("IntakeForm.tsx: 'Change Order' now selectable as a document type for normal reviews too.")
PYEOF

echo ""
echo "Restart your dev server and check a client's page:"
echo "  1. New 'Executed agreements' card below Client notes — pick a type"
echo "     (MSA/SOW/Change Order/Other), optionally add a label, upload a"
echo "     file. It should appear in the list above the form, labeled and"
echo "     linking to Drive."
echo "  2. Upload a couple with different types (e.g. two Change Orders) —"
echo "     confirm they both show up distinctly, most recent first."
echo "  3. 'Remove' deletes the Firestore record (the file itself stays in"
echo "     Drive, only the reference here is removed)."
echo "  4. If step 6 above found DOC_TYPES, also check the normal intake"
echo "     form's 'Document type' dropdown now offers Change Order too."
echo ""
echo "One more manual step this script can't do for you: since you added a"
echo "new Firestore security rule, deploy it with:"
echo "  firebase deploy --only firestore:rules"
echo ""
echo "Then commit and push the code changes (via GitHub Desktop) to deploy."
