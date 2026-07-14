#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_executed_agreement_project.sh
set -e

# ── 1. types.ts — ExecutedAgreementDoc gets optional project fields ─────────
python3 - << 'PYEOF'
path = "src/lib/types.ts"
with open(path) as f:
    content = f.read()

if "projectNumber: string | null" in content and "ExecutedAgreementDoc" in content:
    print("types.ts: already present — nothing to do.")
else:
    old = """export interface ExecutedAgreementDoc {
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
    new = """export interface ExecutedAgreementDoc {
  id: string;
  docType: DocType;
  // Free-text description, e.g. "Change Order #2 — Additional Deliverables"
  // — optional since a single MSA/SOW often doesn't need one.
  label: string;
  driveFileId: string;
  driveUrl: string;
  // Which job this is filed under — required for SOW/Change Order (always
  // job-specific), null for MSA/Other left at the client level (an MSA
  // typically governs many jobs, not just one).
  projectNumber: string | null;
  projectName: string | null;
  executedDate: string | null;
  uploadedAt: number;
  uploadedBy: { name: string; email: string };
}"""
    if old not in content:
        raise SystemExit("Expected ExecutedAgreementDoc block not found in types.ts — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("types.ts: added projectNumber/projectName to ExecutedAgreementDoc.")
PYEOF

# ── 2. upload-executed-agreement route — file under the matter's doc-type folder when a project is given ──
cat > src/app/api/drive/upload-executed-agreement/route.ts << 'EOF'
import { NextRequest, NextResponse } from 'next/server';
import { ensureClientFolder, ensureMatterFolder, ensureDocTypeFolder, uploadFileToFolder } from '@/lib/drive/client';

// Uploads a fully executed/signed agreement — separate from the review
// pipeline's versions, since an executed copy (often countersigned
// externally, after negotiation) doesn't correspond to any single reviewed
// draft. Filed under Contract Reviews/{Client}/{Job Number — Project}/{Doc
// Type}/ when a project is given, alongside that job's review history —
// falls back to Contract Reviews/{Client}/{Doc Type}/ when no project is
// given, since an MSA is normally client-wide rather than tied to one job.
export async function POST(req: NextRequest) {
  try {
    const form = await req.formData();
    const file = form.get('file') as File | null;
    const clientName = form.get('clientName') as string | null;
    const docType = form.get('docType') as string | null;
    const label = (form.get('label') as string | null) ?? '';
    const projectNumber = (form.get('projectNumber') as string | null) || '';
    const projectName = (form.get('projectName') as string | null) || '';

    if (!file || !clientName || !docType) {
      return NextResponse.json({ error: 'file, clientName, and docType are required.' }, { status: 400 });
    }

    let targetFolderId: string;
    if (projectNumber && projectName) {
      const projectLabel = `${projectNumber} — ${projectName}`;
      const { matterFolderId } = await ensureMatterFolder(clientName, projectLabel);
      targetFolderId = await ensureDocTypeFolder(matterFolderId, docType);
    } else {
      const { folderId: clientFolderId } = await ensureClientFolder(clientName);
      targetFolderId = await ensureDocTypeFolder(clientFolderId, docType);
    }

    const buffer = Buffer.from(await file.arrayBuffer());

    const namePrefix = label ? `${docType} — ${label}` : docType;
    const { fileId, webViewLink } = await uploadFileToFolder({
      folderId: targetFolderId,
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
echo "upload-executed-agreement/route.ts: now files under the matter's doc-type folder when a project is picked."

# ── 3. ClientDetailView.tsx — project picker + validation + Drive folder wiring ──
python3 - << 'PYEOF'
path = "src/components/library/ClientDetailView.tsx"
with open(path) as f:
    content = f.read()

if "agreementProjectKey" in content:
    print("ClientDetailView.tsx: already present — nothing to do.")
else:
    # 3a. new state
    old_state = """  const [executedAgreements, setExecutedAgreements] = useState<ExecutedAgreementDoc[]>([]);
  const [agreementDocType, setAgreementDocType] = useState<DocType>('SOW');
  const [agreementLabel, setAgreementLabel] = useState('');
  const [uploadingAgreement, setUploadingAgreement] = useState(false);
  const [agreementError, setAgreementError] = useState<string | null>(null);
  const { user } = useAuth();"""
    new_state = """  const [executedAgreements, setExecutedAgreements] = useState<ExecutedAgreementDoc[]>([]);
  const [agreementDocType, setAgreementDocType] = useState<DocType>('SOW');
  const [agreementLabel, setAgreementLabel] = useState('');
  const [agreementProjectKey, setAgreementProjectKey] = useState('');
  const [agreementNewProjectNumber, setAgreementNewProjectNumber] = useState('');
  const [agreementNewProjectName, setAgreementNewProjectName] = useState('');
  const [uploadingAgreement, setUploadingAgreement] = useState(false);
  const [agreementError, setAgreementError] = useState<string | null>(null);
  const { user } = useAuth();"""

    # 3b. project options + resolver, placed right after msaContract lookup
    old_msa = """  const msaContract = contracts.find((c) => c.id === client.msaContractId);"""
    new_msa = """  const msaContract = contracts.find((c) => c.id === client.msaContractId);

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
  }"""

    # 3c. handleUploadAgreement — validate + pass project through
    old_handler = """  async function handleUploadAgreement(e: React.ChangeEvent<HTMLInputElement>) {
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

    # 3d. list item — show which project it's filed under
    old_list_item = """                <div>
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
                </div>"""
    new_list_item = """                <div>
                  <span className="mr-2 rounded-full border border-rule px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide text-ink-faint">
                    {a.docType}
                  </span>
                  {a.projectNumber && (
                    <span className="mr-2 font-mono text-[10px] text-ink-faint">
                      {a.projectNumber} — {a.projectName}
                    </span>
                  )}
                  <a
                    href={a.driveUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="font-body text-sm text-accent hover:underline"
                  >
                    {a.label || a.docType} ↗
                  </a>
                </div>"""

    # 3e. form — insert a Project field between Type and Label
    old_form = """          <label className="block">
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
        {agreementError && <p className="mt-2 text-sm text-high">{agreementError}</p>}"""
    new_form = """          <label className="block">
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
        {agreementError && <p className="mt-2 text-sm text-high">{agreementError}</p>}"""

    missing = [
        l for l, n in [
            ("state", old_state),
            ("msaContract anchor", old_msa),
            ("handler", old_handler),
            ("list item", old_list_item),
            ("form", old_form),
        ] if n not in content
    ]
    if missing:
        raise SystemExit(f"Expected block(s) not found in ClientDetailView.tsx: {missing} — aborting.")

    content = (
        content.replace(old_state, new_state)
        .replace(old_msa, new_msa)
        .replace(old_handler, new_handler)
        .replace(old_list_item, new_list_item)
        .replace(old_form, new_form)
    )
    with open(path, "w") as f:
        f.write(content)
    print("ClientDetailView.tsx: added the project picker to Executed agreements.")
PYEOF

echo ""
echo "Restart your dev server and check a client with at least one matter on file:"
echo "  1. Pick 'SOW' or 'Change Order' as the type — a Project dropdown appears,"
echo "     listing that client's existing jobs plus '+ New project…'. Uploading"
echo "     without picking one should show an error instead of uploading."
echo "  2. Pick an existing project, upload a file — in Drive, confirm it lands"
echo "     in Contract Reviews/{Client}/{Job Number — Project}/{Doc Type}/,"
echo "     not the client's top-level folder."
echo "  3. Pick '+ New project…', type a job number/name that has no matter yet,"
echo "     upload — confirm Drive creates that job folder fresh."
echo "  4. Pick 'MSA' — the Project field should say '(optional)' and be safe"
echo "     to leave on '— none (client-level) —'; that upload should still land"
echo "     in Contract Reviews/{Client}/MSA/ like before."
echo "  5. Existing executed agreements in the list without a project should"
echo "     display unchanged; new ones filed under a project should show the"
echo "     job number/name next to the type badge."
echo ""
echo "Then commit and push (via GitHub Desktop) to deploy."
