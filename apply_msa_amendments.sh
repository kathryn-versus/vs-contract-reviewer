#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_msa_amendments.sh
set -e

# ── 1. types.ts — MsaAmendmentDoc + ClientDoc.msaAmendments ─────────────────
python3 - << 'PYEOF'
path = "src/lib/types.ts"
with open(path) as f:
    content = f.read()

if "MsaAmendmentDoc" in content:
    print("types.ts: already present — nothing to do.")
else:
    old_interface_start = """export interface ClientDoc {
  id: string;
  name: string;
  slug: string;
  notes: string;"""
    new_interface_start = """export interface MsaAmendmentDoc {
  id: string;
  fileName: string;
  driveFileId: string;
  driveUrl: string;
  uploadedAt: number;
}

export interface ClientDoc {
  id: string;
  name: string;
  slug: string;
  notes: string;"""
    if old_interface_start not in content:
        raise SystemExit("Expected ClientDoc opening not found in types.ts — aborting.")
    content = content.replace(old_interface_start, new_interface_start)

    old_field = """  noMsa: boolean;
  createdAt: number;
  createdBy: string;
}"""
    new_field = """  noMsa: boolean;
  // Amendments to the governing MSA — optional/missing means none yet. Text
  // is pulled from Drive and appended to the MSA context given to Claude on
  // every future SOW review (see getGoverningMsaContext), so an amendment
  // automatically factors into the "MSA alignment" concern without any extra
  // setup per review.
  msaAmendments?: MsaAmendmentDoc[];
  createdAt: number;
  createdBy: string;
}"""
    if old_field not in content:
        raise SystemExit("Expected noMsa field not found in types.ts — aborting.")
    content = content.replace(old_field, new_field)

    with open(path, "w") as f:
        f.write(content)
    print("types.ts: added MsaAmendmentDoc and ClientDoc.msaAmendments.")
PYEOF

# ── 2. firestore.ts — addMsaAmendment / removeMsaAmendment ──────────────────
python3 - << 'PYEOF'
path = "src/lib/firebase/firestore.ts"
with open(path) as f:
    content = f.read()

if "addMsaAmendment" in content:
    print("firestore.ts: already present — nothing to do.")
else:
    old_import = """import { deleteDoc,
  collection,
  collectionGroup,
  doc,
  getDoc,
  getDocs,
  addDoc,
  setDoc,
  updateDoc,
  query,
  where,
  orderBy,
  limit as fsLimit,
  serverTimestamp,
  Timestamp,
  onSnapshot,
} from 'firebase/firestore';
import { db } from './client';
import type { ClientDoc, ContractDoc, VersionDoc, Finding, IssueThreadDoc, ThreadMessage, UserDoc, Role, ExecutedAgreementDoc } from '../types';"""
    new_import = """import { deleteDoc,
  collection,
  collectionGroup,
  doc,
  getDoc,
  getDocs,
  addDoc,
  setDoc,
  updateDoc,
  query,
  where,
  orderBy,
  limit as fsLimit,
  serverTimestamp,
  Timestamp,
  onSnapshot,
  arrayUnion,
  arrayRemove,
} from 'firebase/firestore';
import { db } from './client';
import type { ClientDoc, ContractDoc, VersionDoc, Finding, IssueThreadDoc, ThreadMessage, UserDoc, Role, ExecutedAgreementDoc, MsaAmendmentDoc } from '../types';"""
    if old_import not in content:
        raise SystemExit("Expected firestore.ts import block not found — aborting.")
    content = content.replace(old_import, new_import)

    old_anchor = """export async function setClientNoMsa(clientId: string, noMsa: boolean) {
  await updateDoc(
    doc(db, 'clients', clientId),
    noMsa ? { noMsa: true, msaDriveFileId: null, msaDriveUrl: null } : { noMsa: false }
  );
}

// ── Contracts & Versions ─────────────────────────────────────────────────"""
    new_anchor = """export async function setClientNoMsa(clientId: string, noMsa: boolean) {
  await updateDoc(
    doc(db, 'clients', clientId),
    noMsa ? { noMsa: true, msaDriveFileId: null, msaDriveUrl: null } : { noMsa: false }
  );
}

// Amendments to the governing MSA — stored as a simple array on the client
// doc (not a subcollection) since there's usually only a handful. Each
// amendment's text is pulled from Drive alongside the base MSA and included
// as extra context on every future SOW review (see getGoverningMsaContext),
// so an amendment is picked up automatically without re-running anything.
export async function addMsaAmendment(clientId: string, amendment: MsaAmendmentDoc) {
  await updateDoc(doc(db, 'clients', clientId), { msaAmendments: arrayUnion(amendment) });
}

export async function removeMsaAmendment(clientId: string, amendment: MsaAmendmentDoc) {
  await updateDoc(doc(db, 'clients', clientId), { msaAmendments: arrayRemove(amendment) });
}

// ── Contracts & Versions ─────────────────────────────────────────────────"""
    if old_anchor not in content:
        raise SystemExit("Expected setClientNoMsa not found in firestore.ts — aborting.")
    content = content.replace(old_anchor, new_anchor)

    with open(path, "w") as f:
        f.write(content)
    print("firestore.ts: added addMsaAmendment and removeMsaAmendment.")
PYEOF

# ── 3. New Drive upload route for amendments ─────────────────────────────────
python3 - << 'PYEOF'
import os
path = "src/app/api/drive/upload-msa-amendment/route.ts"
if os.path.exists(path):
    print("upload-msa-amendment/route.ts: already present — nothing to do.")
else:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    content = """import { NextRequest, NextResponse } from 'next/server';
import { ensureClientFolder, uploadFileToFolder } from '@/lib/drive/client';

// Uploads an MSA amendment straight to the client's Drive folder, alongside
// the MSA itself — same no-analysis, direct-upload pattern as
// /api/drive/upload-msa. Its text is pulled back out at review time by
// getGoverningMsaContext and folded into the MSA context given to Claude, so
// it's automatically considered on every future SOW review for this client.
export async function POST(req: NextRequest) {
  try {
    const form = await req.formData();
    const file = form.get('file') as File | null;
    const clientName = form.get('clientName') as string | null;

    if (!file || !clientName) {
      return NextResponse.json({ error: 'file and clientName are required.' }, { status: 400 });
    }

    const { folderId } = await ensureClientFolder(clientName);
    const buffer = Buffer.from(await file.arrayBuffer());

    const { fileId, webViewLink } = await uploadFileToFolder({
      folderId,
      fileName: `MSA Amendment — ${file.name}`,
      mimeType: file.type || 'application/octet-stream',
      buffer,
    });

    return NextResponse.json({ fileId, webViewLink });
  } catch (err) {
    console.error('drive/upload-msa-amendment failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Amendment upload failed.' },
      { status: 500 }
    );
  }
}
"""
    with open(path, "w") as f:
        f.write(content)
    print("Created src/app/api/drive/upload-msa-amendment/route.ts.")
PYEOF

# ── 4. msaContext.ts — pull amendment text alongside the base MSA ───────────
python3 - << 'PYEOF'
path = "src/lib/drive/msaContext.ts"
with open(path) as f:
    content = f.read()

if "msaAmendments" in content:
    print("msaContext.ts: already present — nothing to do.")
else:
    new_content = '''import 'server-only';
import { adminDb } from '@/lib/firebase/admin';
import { downloadFileBuffer } from './client';
import { extractDocText } from './extractDocText';

const MAX_MSA_CHARS = 20_000;
const MAX_AMENDMENT_CHARS = 8_000;

/**
 * Pulls this client's governing MSA text (plus any amendments filed against
 * it) from Drive so it can be fed to Claude as context on a review — no
 * manual re-entry of standing positions required. The base MSA is resolved
 * from one of two sources, in order:
 *   1. A directly-uploaded MSA file (Library → client page → "Upload MSA") —
 *      the simpler, no-analysis path.
 *   2. A fully-reviewed matter designated as governing MSA (Library →
 *      matter → "Set as governing MSA") — the original flow.
 * Any amendments (Library → client page → "+ Add amendment") are appended
 * below the base text, each in its own clearly-labeled block, so Claude
 * treats them as modifying the base MSA rather than as unrelated documents.
 * Returns null (never throws) if there's neither an MSA nor an amendment on
 * file, or extraction fails for everything — MSA context is a nice-to-have
 * and should never block a review. A single amendment failing to extract
 * doesn't drop the rest, or the base MSA text.
 */
export async function getGoverningMsaContext(clientId: string): Promise<string | null> {
  try {
    const clientSnap = await adminDb().collection('clients').doc(clientId).get();
    if (!clientSnap.exists) return null;
    const clientData = clientSnap.data();

    let msaDriveFileId = clientData?.msaDriveFileId as string | null | undefined;

    if (!msaDriveFileId) {
      const msaContractId = clientData?.msaContractId as string | null | undefined;
      if (msaContractId) {
        const contractSnap = await adminDb().collection('contracts').doc(msaContractId).get();
        if (contractSnap.exists) {
          msaDriveFileId = contractSnap.data()?.driveFileId as string | null | undefined;
        }
      }
    }

    let msaText: string | null = null;
    if (msaDriveFileId) {
      try {
        const { buffer, mimeType, name } = await downloadFileBuffer(msaDriveFileId);
        const extracted = await extractDocText(buffer, mimeType, name);
        msaText = extracted ? extracted.slice(0, MAX_MSA_CHARS) : null;
      } catch (err) {
        console.error('getGoverningMsaContext: base MSA extraction failed', err);
      }
    }

    const amendments = (clientData?.msaAmendments ?? []) as {
      fileName?: string;
      driveFileId?: string;
    }[];
    const amendmentBlocks: string[] = [];
    for (const amendment of amendments) {
      if (!amendment?.driveFileId) continue;
      try {
        const { buffer, mimeType, name } = await downloadFileBuffer(amendment.driveFileId);
        const text = await extractDocText(buffer, mimeType, name);
        if (text) {
          amendmentBlocks.push(
            `--- AMENDMENT: ${amendment.fileName ?? name} ---\\n${text.slice(0, MAX_AMENDMENT_CHARS)}`
          );
        }
      } catch (err) {
        console.error('getGoverningMsaContext: amendment extraction failed', err);
      }
    }

    if (!msaText && amendmentBlocks.length === 0) return null;
    return [msaText, ...amendmentBlocks].filter(Boolean).join('\\n\\n');
  } catch (err) {
    console.error('getGoverningMsaContext failed', err);
    return null;
  }
}
'''
    with open(path, "w") as f:
        f.write(new_content)
    print("msaContext.ts: now pulls and appends amendment text alongside the base MSA.")
PYEOF

# ── 5. prompts.ts — mention amendments in the MSA context + alignment concern wording ──
python3 - << 'PYEOF'
path = "src/lib/claude/prompts.ts"
with open(path) as f:
    content = f.read()

if "as amended" in content:
    print("prompts.ts: already present — nothing to do.")
else:
    old_desc = """        description:
          "Compare this document's material terms (payment, termination, liability, indemnification, IP, and anything else both documents address) against the governing MSA provided below. Flag any place where this document conflicts with, narrows, weakens, or fails to honor a protection already established in the MSA. Do not flag a term merely for repeating or incorporating the MSA by reference — only flag genuine conflicts or deviations.",
      }
    : null;"""
    new_desc = """        description:
          "Compare this document's material terms (payment, termination, liability, indemnification, IP, and anything else both documents address) against the governing MSA provided below, as amended. If the MSA context includes one or more sections marked \\"--- AMENDMENT: ... ---\\", treat each amendment's terms as controlling over the original MSA language it modifies — compare against the MSA as amended, not just the original text. Flag any place where this document conflicts with, narrows, weakens, or fails to honor a protection already established in the MSA (as amended). Do not flag a term merely for repeating or incorporating the MSA by reference — only flag genuine conflicts or deviations.",
      }
    : null;"""
    if old_desc not in content:
        raise SystemExit("Expected msaAlignmentConcern description not found in prompts.ts — aborting.")
    content = content.replace(old_desc, new_desc)

    old_label = """  msaContext
    ? `GOVERNING MSA (excerpt, pulled automatically from this client's Drive folder — use it both as background for what's already been negotiated at the master-agreement level (a SOW that simply incorporates MSA terms is not itself an issue) AND as the comparison document for the "MSA alignment" concern below):\\n\"\"\"\\n${msaContext}\\n\"\"\"\\n`
    : ''"""
    new_label = """  msaContext
    ? `GOVERNING MSA (excerpt, pulled automatically from this client's Drive folder, including the text of any amendments filed against it, each marked "--- AMENDMENT: ... ---" — use it both as background for what's already been negotiated at the master-agreement level (a SOW that simply incorporates MSA terms is not itself an issue) AND as the comparison document, as amended, for the "MSA alignment" concern below):\\n\"\"\"\\n${msaContext}\\n\"\"\"\\n`
    : ''"""
    if old_label not in content:
        raise SystemExit("Expected GOVERNING MSA context label not found in prompts.ts — aborting.")
    content = content.replace(old_label, new_label)

    with open(path, "w") as f:
        f.write(content)
    print("prompts.ts: updated wording so amendments are treated as controlling over the base MSA.")
PYEOF

# ── 6. ClientDetailView.tsx — upload/list/remove amendments on the client page ──
python3 - << 'PYEOF'
path = "src/components/library/ClientDetailView.tsx"
with open(path) as f:
    content = f.read()

if "handleUploadAmendment" in content:
    print("ClientDetailView.tsx: already present — nothing to do.")
else:
    old_import = """  setContractMarkedReceived,
  deleteContract,
  setExecutedAgreementContract,
} from '@/lib/firebase/firestore';"""
    new_import = """  setContractMarkedReceived,
  deleteContract,
  setExecutedAgreementContract,
  addMsaAmendment,
  removeMsaAmendment,
} from '@/lib/firebase/firestore';"""
    if old_import not in content:
        raise SystemExit("Expected firestore import block not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_import, new_import)

    old_type_import = "import type { ClientDoc, ContractDoc, DocType, ExecutedAgreementDoc } from '@/lib/types';"
    new_type_import = "import type { ClientDoc, ContractDoc, DocType, ExecutedAgreementDoc, MsaAmendmentDoc } from '@/lib/types';"
    if old_type_import not in content:
        raise SystemExit("Expected types import not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_type_import, new_type_import)

    old_state = """  const [uploadingAgreement, setUploadingAgreement] = useState(false);
  const [agreementError, setAgreementError] = useState<string | null>(null);
  const [reconnecting, setReconnecting] = useState(false);
  const { user } = useAuth();"""
    new_state = """  const [uploadingAgreement, setUploadingAgreement] = useState(false);
  const [agreementError, setAgreementError] = useState<string | null>(null);
  const [reconnecting, setReconnecting] = useState(false);
  const [uploadingAmendment, setUploadingAmendment] = useState(false);
  const [amendmentError, setAmendmentError] = useState<string | null>(null);
  const { user } = useAuth();"""
    if old_state not in content:
        raise SystemExit("Expected agreementError/reconnecting state not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_state, new_state)

    old_handlers = """  async function handleClearMsaFile() {
    if (!client) return;
    await clearClientMsaFile(clientId);
    getClient(clientId).then(setClient);
  }

  async function handleSetNoMsa(value: boolean) {"""
    new_handlers = """  async function handleClearMsaFile() {
    if (!client) return;
    await clearClientMsaFile(clientId);
    getClient(clientId).then(setClient);
  }

  async function handleUploadAmendment(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file || !client) return;
    setUploadingAmendment(true);
    setAmendmentError(null);
    try {
      const form = new FormData();
      form.append('file', file);
      form.append('clientName', client.name);
      const res = await fetch('/api/drive/upload-msa-amendment', { method: 'POST', body: form });
      const data = await res.json();
      if (data.error) throw new Error(data.error);
      await addMsaAmendment(clientId, {
        id: crypto.randomUUID(),
        fileName: file.name,
        driveFileId: data.fileId,
        driveUrl: data.webViewLink,
        uploadedAt: Date.now(),
      });
      getClient(clientId).then(setClient);
    } catch (err) {
      setAmendmentError(err instanceof Error ? err.message : 'Amendment upload failed.');
    } finally {
      setUploadingAmendment(false);
    }
  }

  async function handleRemoveAmendment(amendment: MsaAmendmentDoc) {
    if (!client) return;
    await removeMsaAmendment(clientId, amendment);
    getClient(clientId).then(setClient);
  }

  async function handleSetNoMsa(value: boolean) {"""
    if old_handlers not in content:
        raise SystemExit("Expected handleClearMsaFile/handleSetNoMsa not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_handlers, new_handlers)

    old_panel_anchor = """      )}

      <Card className="p-5">
        <p className="mb-2 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
          Client notes — fed to Claude as context on future reviews
        </p>"""
    new_panel_anchor = """      )}

      {(msaContract || client.msaDriveFileId) && (
        <Card className="p-5">
          <p className="mb-2 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
            MSA amendments — included alongside the MSA as context on every future SOW review
          </p>
          {(client.msaAmendments ?? []).length > 0 && (
            <div className="mb-3 space-y-2">
              {(client.msaAmendments ?? []).map((amendment) => (
                <div
                  key={amendment.id}
                  className="flex items-center justify-between border-b border-rule pb-2 last:border-0 last:pb-0"
                >
                  <a
                    href={amendment.driveUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="font-body text-sm text-accent hover:underline"
                  >
                    {amendment.fileName} ↗
                  </a>
                  <button
                    type="button"
                    onClick={() => handleRemoveAmendment(amendment)}
                    className="font-mono text-xs text-ink-faint hover:text-high"
                  >
                    Remove
                  </button>
                </div>
              ))}
            </div>
          )}
          <label className="inline-block cursor-pointer rounded-sm border border-rule px-3 py-1.5 font-mono text-xs uppercase tracking-wide text-ink-soft hover:border-ink">
            {uploadingAmendment ? 'Uploading…' : '+ Add amendment'}
            <input
              type="file"
              accept=".pdf,.docx,.txt"
              className="hidden"
              onChange={handleUploadAmendment}
              disabled={uploadingAmendment}
            />
          </label>
          {amendmentError && <p className="mt-2 text-sm text-high">{amendmentError}</p>}
        </Card>
      )}

      <Card className="p-5">
        <p className="mb-2 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
          Client notes — fed to Claude as context on future reviews
        </p>"""
    if old_panel_anchor not in content:
        raise SystemExit("Expected Client notes panel anchor not found in ClientDetailView.tsx — aborting.")
    content = content.replace(old_panel_anchor, new_panel_anchor)

    with open(path, "w") as f:
        f.write(content)
    print("ClientDetailView.tsx: added the MSA Amendments panel (upload / list / remove).")
PYEOF

echo ""
echo "Restart your dev server and check a client that has a governing MSA on"
echo "file (either an uploaded MSA file or a matter set as governing MSA):"
echo "  1. A new 'MSA amendments' card should appear below the Governing MSA"
echo "     card, with a '+ Add amendment' button."
echo "  2. Upload a short amendment doc (pdf/docx/txt) — it should appear"
echo "     listed with a link to Drive and a 'Remove' link."
echo "  3. Run (or re-run) a SOW review for that client — the amendment's"
echo "     terms are now pulled in alongside the MSA and Claude is told to"
echo "     treat them as controlling over the original MSA language they"
echo "     modify, for the 'MSA alignment' concern."
echo "  4. This only affects reviews run AFTER an amendment is added —"
echo "     it doesn't retroactively re-flag SOWs already reviewed."
echo ""
echo "Then npm run build, commit, and push (via GitHub Desktop) to deploy."
