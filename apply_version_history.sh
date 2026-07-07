#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_version_history.sh
set -e

# ── 1. Add per-version Drive/Doc/report fields to VersionDoc ────────────────
# Uses python3 to patch just the VersionDoc block in types.ts, rather than
# retyping the whole file — that file also holds the full STANDING_CONCERNS
# text (long payment-terms paragraph with lots of quotes), which is safer left
# untouched. Aborts loudly instead of guessing if the block isn't found.

python3 - << 'PYEOF'
path = "src/lib/types.ts"
with open(path) as f:
    content = f.read()

old = """export interface VersionDoc {
  id: string;
  versionNumber: number;
  uploadedAt: number;
  uploadedBy: { name: string; email: string };
  fileName: string;
  characterCount: number;
  findings: Finding[];
  deltaFromPrevious: string | null;
  reportUrl: string | null;
}"""

new = """export interface VersionDoc {
  id: string;
  versionNumber: number;
  uploadedAt: number;
  uploadedBy: { name: string; email: string };
  fileName: string;
  characterCount: number;
  findings: Finding[];
  deltaFromPrevious: string | null;
  // Per-version Drive links — kept on each version (not just the top-level
  // ContractDoc) so version history survives later uploads instead of being
  // silently overwritten by the next version's links. Populated once the
  // Drive upload / Google Doc duplication / report uploads for THIS version
  // succeed; null until then.
  driveFileId: string | null;
  driveUrl: string | null;
  driveFolderId: string | null;
  driveFolderUrl: string | null;
  googleDocId: string | null;
  googleDocUrl: string | null;
  reportHtmlUrl: string | null;
  reportPdfUrl: string | null;
}"""

if old not in content:
    raise SystemExit("VersionDoc block not found as expected in src/lib/types.ts — aborting so nothing is silently corrupted. Paste me the current file and I'll redo this by hand.")

content = content.replace(old, new)
with open(path, "w") as f:
    f.write(content)
print("Patched: src/lib/types.ts (VersionDoc)")
PYEOF

# ── 2. Add updateVersionDrive to firestore.ts ───────────────────────────────

mkdir -p "$(dirname "src/lib/firebase/firestore.ts")"
cat > "src/lib/firebase/firestore.ts" << 'VS_APPLY_EOF_vh1'
'use client';

import {
  collection,
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
import type { ClientDoc, ContractDoc, VersionDoc, Finding, IssueThreadDoc, ThreadMessage, UserDoc, Role } from '../types';

function slugify(name: string) {
  return name
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '');
}

function toMillis(v: unknown): number {
  if (v instanceof Timestamp) return v.toMillis();
  if (typeof v === 'number') return v;
  return Date.now();
}

// ── Clients ──────────────────────────────────────────────────────────────

export async function listClients(): Promise<ClientDoc[]> {
  const snap = await getDocs(query(collection(db, 'clients'), orderBy('name')));
  return snap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<ClientDoc, 'id'>), createdAt: toMillis(d.data().createdAt) }));
}

export function subscribeClients(cb: (clients: ClientDoc[]) => void) {
  return onSnapshot(query(collection(db, 'clients'), orderBy('name')), (snap) => {
    cb(snap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<ClientDoc, 'id'>), createdAt: toMillis(d.data().createdAt) })));
  });
}

export async function getOrCreateClient(name: string, createdBy: string): Promise<ClientDoc> {
  const slug = slugify(name);
  const existing = await getDocs(query(collection(db, 'clients'), where('slug', '==', slug), fsLimit(1)));
  if (!existing.empty) {
    const d = existing.docs[0];
    return { id: d.id, ...(d.data() as Omit<ClientDoc, 'id'>), createdAt: toMillis(d.data().createdAt) };
  }
  const ref = await addDoc(collection(db, 'clients'), {
    name,
    slug,
    notes: '',
    msaContractId: null,
    createdAt: serverTimestamp(),
    createdBy,
  });
  const snap = await getDoc(ref);
  return { id: ref.id, ...(snap.data() as Omit<ClientDoc, 'id'>), createdAt: Date.now() };
}

export async function updateClientNotes(clientId: string, notes: string) {
  await updateDoc(doc(db, 'clients', clientId), { notes });
}

export async function getClient(clientId: string): Promise<ClientDoc | null> {
  const snap = await getDoc(doc(db, 'clients', clientId));
  if (!snap.exists()) return null;
  return { id: snap.id, ...(snap.data() as Omit<ClientDoc, 'id'>), createdAt: toMillis(snap.data().createdAt) };
}

// ── Contracts & Versions ─────────────────────────────────────────────────

export async function createContract(input: Omit<ContractDoc, 'id' | 'createdAt' | 'latestVersionId'>): Promise<string> {
  const ref = await addDoc(collection(db, 'contracts'), {
    ...input,
    createdAt: serverTimestamp(),
    latestVersionId: null,
  });
  return ref.id;
}

export async function addVersion(
  contractId: string,
  input: Omit<VersionDoc, 'id' | 'uploadedAt'>
): Promise<string> {
  const versionsRef = collection(db, 'contracts', contractId, 'versions');
  const ref = await addDoc(versionsRef, { ...input, uploadedAt: serverTimestamp() });
  await updateDoc(doc(db, 'contracts', contractId), { latestVersionId: ref.id });
  return ref.id;
}

export async function listVersionsForContract(contractId: string): Promise<VersionDoc[]> {
  const snap = await getDocs(
    query(collection(db, 'contracts', contractId, 'versions'), orderBy('versionNumber', 'desc'))
  );
  return snap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<VersionDoc, 'id'>), uploadedAt: toMillis(d.data().uploadedAt) }));
}

export async function listContractsForClient(clientId: string): Promise<ContractDoc[]> {
  const snap = await getDocs(
    query(collection(db, 'contracts'), where('clientId', '==', clientId), orderBy('createdAt', 'desc'))
  );
  return snap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<ContractDoc, 'id'>), createdAt: toMillis(d.data().createdAt) }));
}

// All matters across every client — used by the intake form's job picker so
// a job can be searched/selected before (or instead of) picking a client.
export async function listAllContracts(): Promise<ContractDoc[]> {
  const snap = await getDocs(query(collection(db, 'contracts'), orderBy('createdAt', 'desc')));
  return snap.docs.map((d) => ({ id: d.id, ...(d.data() as Omit<ContractDoc, 'id'>), createdAt: toMillis(d.data().createdAt) }));
}

// Next version number for an existing matter — used when a reviewer picks an
// existing job from the intake form instead of creating a new one.
export async function getNextVersionNumber(contractId: string): Promise<number> {
  const versions = await listVersionsForContract(contractId);
  return (versions[0]?.versionNumber ?? 0) + 1;
}

export async function updateContractDrive(
  contractId: string,
  drive: { driveFileId: string; driveUrl: string; driveFolderUrl: string; driveFolderId?: string }
) {
  await updateDoc(doc(db, 'contracts', contractId), drive);
}

/**
 * Updates Drive/Google Doc/report links on a SPECIFIC version, not the
 * contract as a whole — this is what lets the Library show correct links for
 * every past version instead of every version pointing at whatever the
 * latest upload happened to be.
 */
export async function updateVersionDrive(
  contractId: string,
  versionId: string,
  drive: Partial<
    Pick<
      VersionDoc,
      | 'driveFileId'
      | 'driveUrl'
      | 'driveFolderId'
      | 'driveFolderUrl'
      | 'googleDocId'
      | 'googleDocUrl'
      | 'reportHtmlUrl'
      | 'reportPdfUrl'
    >
  >
) {
  await updateDoc(doc(db, 'contracts', contractId, 'versions', versionId), drive);
}

export async function moveContract(
  contractId: string,
  updates: Partial<Pick<ContractDoc, 'clientId' | 'clientName' | 'projectName'>>
) {
  await updateDoc(doc(db, 'contracts', contractId), updates);
}

// Marks a contract as the client's governing MSA — feeds automatic MSA
// context into future SOW reviews for that client (brief §11, Phase 2).
export async function setGoverningMsa(clientId: string, contractId: string) {
  await updateDoc(doc(db, 'clients', clientId), { msaContractId: contractId });
}

export async function clearGoverningMsa(clientId: string) {
  await updateDoc(doc(db, 'clients', clientId), { msaContractId: null });
}

// ── Issue threads (redline chat) ─────────────────────────────────────────

export async function getIssueThread(
  contractId: string,
  versionId: string,
  issueUid: string
): Promise<ThreadMessage[]> {
  const ref = doc(db, 'contracts', contractId, 'versions', versionId, 'issueThreads', issueUid);
  const snap = await getDoc(ref);
  if (!snap.exists()) return [];
  return (snap.data() as IssueThreadDoc).messages ?? [];
}

export async function appendIssueThreadMessages(
  contractId: string,
  versionId: string,
  issueUid: string,
  newMessages: ThreadMessage[]
) {
  const ref = doc(db, 'contracts', contractId, 'versions', versionId, 'issueThreads', issueUid);
  const existing = await getDoc(ref);
  const prior: ThreadMessage[] = existing.exists() ? (existing.data() as IssueThreadDoc).messages ?? [] : [];
  await setDoc(ref, { messages: [...prior, ...newMessages] }, { merge: true });
}

// ── Users / admin management ─────────────────────────────────────────────

export async function listUsers(): Promise<UserDoc[]> {
  const snap = await getDocs(query(collection(db, 'users'), orderBy('email')));
  return snap.docs.map((d) => ({
    uid: d.id,
    ...(d.data() as Omit<UserDoc, 'uid'>),
    createdAt: toMillis(d.data().createdAt),
    lastLoginAt: toMillis(d.data().lastLoginAt),
  }));
}

export async function setUserRole(uid: string, role: Role) {
  await updateDoc(doc(db, 'users', uid), { role });
}
VS_APPLY_EOF_vh1

# ── 3. googleDocsHandoff.ts — surface docId (the API already sends it back) ─

mkdir -p "$(dirname "src/lib/report/googleDocsHandoff.ts")"
cat > "src/lib/report/googleDocsHandoff.ts" << 'VS_APPLY_EOF_vh2'
// "Open in Google Docs" duplicates the full source contract (not just
// drafted redlines) into a native Google Doc saved in the matter's Drive
// folder, via /api/drive/duplicate-to-docs. Requires the contract to already
// have a driveFileId + driveFolderId (i.e. the Drive upload step succeeded).
export async function duplicateContractToGoogleDocs(params: {
  fileId: string;
  folderId: string;
  name: string;
}): Promise<{ docId: string; docUrl: string }> {
  const res = await fetch('/api/drive/duplicate-to-docs', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error);
  window.open(data.docUrl, '_blank', 'noopener,noreferrer');
  // The route has always returned docId too — this was just never read on
  // the client side, which is why nothing could persist it or reuse the doc
  // on a repeat click (every click created a fresh duplicate copy instead).
  return { docId: data.docId, docUrl: data.docUrl };
}
VS_APPLY_EOF_vh2

# ── 4. page.tsx — persist per-version Drive links, pass versionNumber down ──

mkdir -p "$(dirname "src/app/page.tsx")"
cat > "src/app/page.tsx" << 'VS_APPLY_EOF_vh3'
'use client';

import { useState } from 'react';
import { AuthGuard } from '@/components/layout/AuthGuard';
import { AppShell } from '@/components/layout/AppShell';
import { IntakeForm, type IntakeValues } from '@/components/intake/IntakeForm';
import { LoadingScan } from '@/components/ui/LoadingScan';
import { ResultsView } from '@/components/review/ResultsView';
import { ConcernIndex } from '@/components/review/ConcernIndex';
import { Button } from '@/components/ui/Button';
import { useAuth } from '@/hooks/useAuth';
import {
  getOrCreateClient,
  createContract,
  addVersion,
  updateContractDrive,
  updateVersionDrive,
  getClient,
  getNextVersionNumber,
} from '@/lib/firebase/firestore';
import { STANDING_CONCERNS } from '@/lib/types';
import type { Finding } from '@/lib/types';

type Step = 'intake' | 'loading' | 'results' | 'error';

export default function ReviewerPage() {
  return (
    <AuthGuard>
      <AppShell>
        <ReviewerFlow />
      </AppShell>
    </AuthGuard>
  );
}

function ReviewerFlow() {
  const { user } = useAuth();
  const [step, setStep] = useState<Step>('intake');
  const [error, setError] = useState<string | null>(null);
  const [findings, setFindings] = useState<Finding[]>([]);
  const [contractMeta, setContractMeta] = useState<{
    contractId: string;
    versionId: string;
    versionNumber: number;
    clientName: string;
    projectName: string;
    projectNumber: string;
    docType: string;
    counterparty: string;
    clientNotes: string | null;
    fileName: string;
    driveFileId: string | null;
    driveFolderId: string | null;
  } | null>(null);

  if (!user) return null;

  async function handleSubmit(values: IntakeValues) {
    setStep('loading');
    setError(null);
    try {
      // 1. Resolve/create the client record and pull any standing notes.
      const client = await getOrCreateClient(values.clientName, user!.email ?? '');
      const clientDoc = await getClient(client.id);

      // 2. Run the standing-concerns analysis. Passing clientId lets the server
      //    auto-pull the client's governing MSA from Drive as extra context.
      const analyzeRes = await fetch('/api/review/analyze', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          docType: values.docType,
          counterparty: values.counterparty,
          clientName: values.clientName,
          clientId: client.id,
          clientNotes: clientDoc?.notes || null,
          documentText: values.documentText,
        }),
      });
      const analyzeData = await analyzeRes.json();
      if (analyzeData.error) throw new Error(analyzeData.error);
      const newFindings: Finding[] = analyzeData.findings;

      // 3. Attach to the existing matter if one was picked, otherwise create
      //    a new contract + first version record in Firestore.
      const isExistingMatter = Boolean(values.existingContractId);
      const contractId = isExistingMatter
        ? values.existingContractId!
        : await createContract({
            clientId: client.id,
            clientName: client.name,
            projectName: values.projectName,
            projectNumber: values.projectNumber,
            docType: values.docType,
            counterparty: values.counterparty,
            submittedBy: { uid: user!.uid, name: user!.displayName ?? user!.email ?? '', email: user!.email ?? '' },
            driveFileId: null,
            driveUrl: null,
            driveFolderUrl: null,
            driveFolderId: null,
          });

      const versionNumber = isExistingMatter ? await getNextVersionNumber(contractId) : 1;
      const versionId = await addVersion(contractId, {
        versionNumber,
        uploadedBy: { name: user!.displayName ?? user!.email ?? '', email: user!.email ?? '' },
        fileName: values.file.name,
        characterCount: values.characterCount,
        findings: newFindings,
        deltaFromPrevious: null,
        // Populated below once the Drive upload (and later, Google Docs /
        // report actions from the results screen) succeed.
        driveFileId: null,
        driveUrl: null,
        driveFolderId: null,
        driveFolderUrl: null,
        googleDocId: null,
        googleDocUrl: null,
        reportHtmlUrl: null,
        reportPdfUrl: null,
      });

      // 4. Upload the source file to Drive (server-side route). For a second
      //    (or later) version of an existing matter, suffix the filename so
      //    it doesn't collide with the prior version already in that folder.
      //    Links are saved on BOTH the contract (a "latest version" pointer,
      //    used e.g. for MSA context auto-pull) and this specific version
      //    (so the Library can show correct links for every past version,
      //    not just whichever was uploaded most recently).
      let driveFileId: string | null = null;
      let driveFolderId: string | null = null;
      try {
        const form = new FormData();
        form.append('file', values.file);
        form.append('clientName', client.name);
        form.append('projectName', values.projectName);
        form.append('projectNumber', values.projectNumber);
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
        }
      } catch {
        // Drive failures shouldn't block the reviewer from seeing results.
      }

      // 5. Fire the email notification (recipients controlled server-side by env vars).
      const counts = {
        high: newFindings.filter((f) => f.severity === 'high').length,
        medium: newFindings.filter((f) => f.severity === 'medium').length,
        low: newFindings.filter((f) => f.severity === 'low').length,
      };
      fetch('/api/gmail/notify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          clientName: client.name,
          projectName: values.projectName,
          severityCounts: counts,
          submittedBy: { name: user!.displayName ?? user!.email ?? '', email: user!.email ?? '' },
          docType: values.docType,
          counterparty: values.counterparty,
          topHighIssues: newFindings.filter((f) => f.severity === 'high'),
          reportDriveUrl: '',
          libraryUrl: `https://vs-contracts.web.app/library/${client.id}`,
        }),
      }).catch(() => {});

      setFindings(newFindings);
      setContractMeta({
        contractId,
        versionId,
        versionNumber,
        clientName: client.name,
        projectName: values.projectName,
        projectNumber: values.projectNumber,
        docType: values.docType,
        counterparty: values.counterparty,
        clientNotes: clientDoc?.notes || null,
        fileName: values.file.name,
        driveFileId,
        driveFolderId,
      });
      setStep('results');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong running the review.');
      setStep('error');
    }
  }

  if (step === 'intake') {
    return <IntakeForm user={user} onSubmit={handleSubmit} submitting={false} />;
  }

  if (step === 'loading') {
    return <LoadingScan />;
  }

  if (step === 'error') {
    return (
      <div className="mx-auto max-w-lg py-16 text-center">
        <p className="mb-4 text-sm text-high">{error}</p>
        <Button onClick={() => setStep('intake')}>Try again</Button>
      </div>
    );
  }

  if (step === 'results' && contractMeta) {
    return (
      <div>
        <div className="mb-4 flex items-baseline justify-between">
          <h1 className="font-display text-3xl text-ink">
            Contract Review <span className="text-accent">VS</span>
          </h1>
          <div className="text-right font-mono text-xs uppercase tracking-wide text-ink-faint">
            Versus Studio
          </div>
        </div>
        <ConcernIndex />
        <div className="mb-6 mt-4 flex items-center justify-between">
          <p className="font-mono text-xs uppercase tracking-wide text-ink-faint">
            {contractMeta.fileName} · {contractMeta.docType} · Reviewed against {STANDING_CONCERNS.length} standing concerns
          </p>
          <Button onClick={() => setStep('intake')}>↻ New review</Button>
        </div>
        <p className="-mt-4 mb-6 font-mono text-xs text-ink-faint">
          {contractMeta.clientName} — {contractMeta.projectName} ({contractMeta.projectNumber}) · Counterparty:{' '}
          {contractMeta.counterparty}
        </p>
        <ResultsView
          contract={contractMeta}
          contractId={contractMeta.contractId}
          versionId={contractMeta.versionId}
          versionNumber={contractMeta.versionNumber}
          findings={findings}
          clientNotes={contractMeta.clientNotes}
          driveFileId={contractMeta.driveFileId}
          driveFolderId={contractMeta.driveFolderId}
          sourceFileName={contractMeta.fileName}
        />
      </div>
    );
  }

  return null;
}
VS_APPLY_EOF_vh3

# ── 5. ResultsView.tsx — idempotent Google Doc reuse + persist all links ────

mkdir -p "$(dirname "src/components/review/ResultsView.tsx")"
cat > "src/components/review/ResultsView.tsx" << 'VS_APPLY_EOF_vh4'
'use client';

import { useMemo, useState } from 'react';
import { Button } from '@/components/ui/Button';
import { SeveritySummary, type FilterValue } from './SeveritySummary';
import { IssueCard } from './IssueCard';
import { PrioritizeDrawer } from './PrioritizeDrawer';
import { RedlineDrawer } from './RedlineDrawer';
import { generateReportHtml, downloadReport } from '@/lib/report/generateReport';
import { downloadReportPdf } from '@/lib/report/generatePdf';
import { duplicateContractToGoogleDocs } from '@/lib/report/googleDocsHandoff';
import { uploadReportToDrive } from '@/lib/report/uploadToDrive';
import { addRedlineCommentsToDoc } from '@/lib/report/addRedlineComments';
import { appendIssueThreadMessages, updateVersionDrive } from '@/lib/firebase/firestore';
import type { ContractDoc, Finding, ThreadMessage } from '@/lib/types';

export function ResultsView({
  contract,
  contractId,
  versionId,
  versionNumber,
  findings,
  clientNotes,
  driveFileId,
  driveFolderId,
  sourceFileName,
}: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  contractId: string;
  versionId: string;
  versionNumber: number;
  findings: Finding[];
  clientNotes?: string | null;
  driveFileId?: string | null;
  driveFolderId?: string | null;
  sourceFileName?: string | null;
}) {
  const [filter, setFilter] = useState<FilterValue>('all');
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [threads, setThreads] = useState<Record<string, ThreadMessage[]>>({});
  const [redlines, setRedlines] = useState<Record<string, string>>({});
  const [prioritizeOpen, setPrioritizeOpen] = useState(false);
  const [redlineOpen, setRedlineOpen] = useState(false);
  const [docsBusy, setDocsBusy] = useState(false);
  const [docsError, setDocsError] = useState<string | null>(null);
  const [googleDocId, setGoogleDocId] = useState<string | null>(null);
  const [googleDocUrl, setGoogleDocUrl] = useState<string | null>(null);
  const [commentsBusy, setCommentsBusy] = useState(false);
  const [commentsError, setCommentsError] = useState<string | null>(null);
  const [commentsAdded, setCommentsAdded] = useState<number | null>(null);

  const visible = useMemo(
    () => (filter === 'all' ? findings : findings.filter((f) => f.severity === filter)),
    [findings, filter]
  );

  const selectedFindings = findings.filter((f) => selected.has(f.uid));
  const redlinedFindings = findings.filter((f) => redlines[f.uid]);

  function toggle(uid: string) {
    setSelected((s) => {
      const next = new Set(s);
      next.has(uid) ? next.delete(uid) : next.add(uid);
      return next;
    });
  }

  function selectAll() {
    setSelected(new Set(findings.map((f) => f.uid)));
  }
  function selectHigh() {
    setSelected(new Set(findings.filter((f) => f.severity === 'high').map((f) => f.uid)));
  }

  async function persistThread(uid: string, messages: ThreadMessage[]) {
    setThreads((t) => ({ ...t, [uid]: messages }));
    await appendIssueThreadMessages(contractId, versionId, uid, messages.slice(threads[uid]?.length ?? 0));
  }

  async function handleShareReportHtml() {
    const html = generateReportHtml({ contract, findings, redlines, fileName: sourceFileName });
    const filename = `${contract.clientName} — ${contract.projectName} review.html`;
    downloadReport(html, filename);

    // Also stash a copy in the same dated Drive folder as the source
    // contract, and persist the link on this version so the Library can
    // surface it later — failures here shouldn't block the local download
    // the reviewer already got.
    if (driveFolderId) {
      try {
        const { driveUrl } = await uploadReportToDrive({
          blob: new Blob([html], { type: 'text/html' }),
          filename,
          folderId: driveFolderId,
        });
        await updateVersionDrive(contractId, versionId, { reportHtmlUrl: driveUrl });
      } catch {
        // Non-fatal — local download already succeeded.
      }
    }
  }

  async function handleDownloadPdf() {
    const filename = `${contract.clientName} — ${contract.projectName} review.pdf`;
    const blob = await downloadReportPdf({ contract, findings, redlines, filename, sourceFileName });

    if (driveFolderId) {
      try {
        const { driveUrl } = await uploadReportToDrive({ blob, filename, folderId: driveFolderId });
        await updateVersionDrive(contractId, versionId, { reportPdfUrl: driveUrl });
      } catch {
        // Non-fatal — local download already succeeded.
      }
    }
  }

  async function handleGoogleDocs() {
    if (!driveFileId || !driveFolderId) return;

    // Reuse the doc already created for this version instead of duplicating
    // again — repeat clicks used to create a fresh "(Google Doc copy)" file
    // in Drive every time.
    if (googleDocId && googleDocUrl) {
      window.open(googleDocUrl, '_blank', 'noopener,noreferrer');
      return;
    }

    setDocsBusy(true);
    setDocsError(null);
    try {
      const { docId, docUrl } = await duplicateContractToGoogleDocs({
        fileId: driveFileId,
        folderId: driveFolderId,
        name: sourceFileName
          ? `${sourceFileName} — v${versionNumber}`
          : `${contract.projectNumber} — ${contract.projectName} — v${versionNumber}`,
      });
      setGoogleDocId(docId);
      setGoogleDocUrl(docUrl);
      await updateVersionDrive(contractId, versionId, { googleDocId: docId, googleDocUrl: docUrl });
    } catch (err) {
      setDocsError(err instanceof Error ? err.message : 'Could not open in Google Docs.');
    } finally {
      setDocsBusy(false);
    }
  }

  async function handleAddRedlineComments() {
    if (!googleDocId || redlinedFindings.length === 0) return;
    setCommentsBusy(true);
    setCommentsError(null);
    setCommentsAdded(null);
    try {
      const { added } = await addRedlineCommentsToDoc({
        fileId: googleDocId,
        items: redlinedFindings.map((f) => ({
          issueTitle: f.issueTitle,
          quote: f.quote,
          redlineText: redlines[f.uid],
        })),
      });
      setCommentsAdded(added);
    } catch (err) {
      setCommentsError(err instanceof Error ? err.message : 'Could not add comments to the Google Doc.');
    } finally {
      setCommentsBusy(false);
    }
  }

  const googleDocsDisabled = !driveFileId || !driveFolderId || docsBusy;
  const addCommentsDisabled = !googleDocId || redlinedFindings.length === 0 || commentsBusy;

  return (
    <div className="space-y-6">
      <SeveritySummary findings={findings} active={filter} onChange={setFilter} />

      <div className="flex flex-wrap items-center gap-2 border-y border-rule py-3">
        <Button variant="ghost" onClick={selectAll}>Select All</Button>
        <Button variant="ghost" onClick={selectHigh}>Select High</Button>
        <div className="flex-1" />
        <Button variant="secondary" onClick={() => setPrioritizeOpen(true)} disabled={findings.length === 0}>
          Prioritize for negotiation
        </Button>
        <Button
          variant="secondary"
          onClick={() => setRedlineOpen(true)}
          disabled={selectedFindings.length === 0}
        >
          Draft redlines ({selectedFindings.length})
        </Button>
        <Button
          variant="secondary"
          onClick={handleGoogleDocs}
          disabled={googleDocsDisabled}
          title={
            !driveFileId || !driveFolderId
              ? 'Waiting on the Drive upload to finish for this matter'
              : googleDocId
                ? 'Reopens the Google Doc already created for this version'
                : undefined
          }
        >
          {docsBusy ? 'Opening…' : googleDocId ? 'Reopen Google Doc' : 'Open in Google Docs'}
        </Button>
        <Button
          variant="secondary"
          onClick={handleAddRedlineComments}
          disabled={addCommentsDisabled}
          title={
            !googleDocId
              ? 'Open in Google Docs first'
              : redlinedFindings.length === 0
                ? 'Draft at least one redline first'
                : undefined
          }
        >
          {commentsBusy ? 'Adding…' : `Add redlines as comments (${redlinedFindings.length})`}
        </Button>
        <Button variant="secondary" onClick={handleShareReportHtml}>
          Download HTML
        </Button>
        <Button variant="primary" onClick={handleDownloadPdf}>
          Download PDF
        </Button>
      </div>

      {docsError && <p className="text-sm text-high">{docsError}</p>}
      {commentsError && <p className="text-sm text-high">{commentsError}</p>}
      {commentsAdded != null && !commentsError && (
        <p className="text-sm text-ink-faint">
          Added {commentsAdded} comment{commentsAdded === 1 ? '' : 's'} to the Google Doc.
        </p>
      )}

      <div className="space-y-3">
        {visible.length === 0 && (
          <p className="py-12 text-center font-mono text-sm text-ink-faint">
            No issues in this filter.
          </p>
        )}
        {visible.map((f, i) => (
          <IssueCard
            key={f.uid}
            index={i}
            finding={f}
            selected={selected.has(f.uid)}
            onToggleSelect={() => toggle(f.uid)}
            clientNotes={clientNotes}
            threadMessages={threads[f.uid] ?? []}
            onPersistThread={(msgs) => persistThread(f.uid, msgs)}
            redlineText={redlines[f.uid]}
          />
        ))}
      </div>

      <PrioritizeDrawer open={prioritizeOpen} onClose={() => setPrioritizeOpen(false)} findings={findings} />
      <RedlineDrawer
        open={redlineOpen}
        onClose={() => setRedlineOpen(false)}
        findings={selectedFindings}
        onDrafted={(results) => {
          setRedlines((r) => {
            const next = { ...r };
            for (const res of results) next[res.uid] = res.redlineText;
            return next;
          });
        }}
      />
    </div>
  );
}
VS_APPLY_EOF_vh4

# ── 6. MatterCard.tsx — per-version links instead of one stale contract link ─

mkdir -p "$(dirname "src/components/library/MatterCard.tsx")"
cat > "src/components/library/MatterCard.tsx" << 'VS_APPLY_EOF_vh5'
'use client';

import { useEffect, useState } from 'react';
import { Card } from '@/components/ui/Card';
import { SeverityBadge } from '@/components/ui/SeverityBadge';
import { listVersionsForContract } from '@/lib/firebase/firestore';
import type { ContractDoc, VersionDoc } from '@/lib/types';

export function MatterCard({
  contract,
  onEdit,
  isGoverningMsa,
  onToggleGoverningMsa,
}: {
  contract: ContractDoc;
  onEdit: () => void;
  isGoverningMsa?: boolean;
  onToggleGoverningMsa?: () => void;
}) {
  const [versions, setVersions] = useState<VersionDoc[]>([]);
  const [expanded, setExpanded] = useState(false);

  useEffect(() => {
    listVersionsForContract(contract.id).then(setVersions).catch(() => {});
  }, [contract.id]);

  const latest = versions[0];
  const counts = latest
    ? {
        high: latest.findings.filter((f) => f.severity === 'high').length,
        medium: latest.findings.filter((f) => f.severity === 'medium').length,
        low: latest.findings.filter((f) => f.severity === 'low').length,
      }
    : null;

  return (
    <Card className="p-5">
      <div className="flex items-start justify-between">
        <div>
          <p className="font-display text-lg text-ink">
            {contract.projectName} <span className="font-mono text-sm text-ink-faint">({contract.projectNumber})</span>
            {isGoverningMsa && (
              <span className="ml-2 rounded-full border border-accent/30 bg-high-bg px-2 py-0.5 align-middle font-mono text-[10px] uppercase tracking-wide text-accent">
                Governing MSA
              </span>
            )}
          </p>
          <p className="font-mono text-xs text-ink-faint">
            {contract.docType} · Counterparty: {contract.counterparty}
          </p>
        </div>
        <div className="flex items-center gap-3">
          {onToggleGoverningMsa && contract.docType !== 'SOW' && (
            <button
              onClick={onToggleGoverningMsa}
              className="font-mono text-xs text-ink-faint hover:text-ink"
            >
              {isGoverningMsa ? 'Unset as MSA' : 'Set as governing MSA'}
            </button>
          )}
          {counts && (
            <div className="flex gap-1">
              {counts.high > 0 && <SeverityBadge severity="high" />}
              {counts.medium > 0 && <SeverityBadge severity="medium" />}
              {counts.low > 0 && <SeverityBadge severity="low" />}
            </div>
          )}
          <button onClick={onEdit} className="font-mono text-xs text-ink-faint hover:text-ink">
            Edit
          </button>
          <button
            onClick={() => setExpanded((v) => !v)}
            className="font-mono text-xs text-ink-faint hover:text-ink"
          >
            {expanded ? 'Hide versions' : `${versions.length} version${versions.length === 1 ? '' : 's'}`}
          </button>
        </div>
      </div>
      {expanded && (
        <div className="mt-4 space-y-4 border-t border-rule pt-4">
          {versions.map((v) => (
            <div key={v.id} className="text-sm">
              <div className="flex items-center justify-between">
                <p className="text-ink">v{v.versionNumber} · {v.fileName}</p>
              </div>
              <p className="font-mono text-xs text-ink-faint">
                {new Date(v.uploadedAt).toLocaleDateString()} · uploaded by {v.uploadedBy.name}
              </p>
              {v.deltaFromPrevious && (
                <p className="mt-1 font-body text-xs text-ink-soft">Δ {v.deltaFromPrevious}</p>
              )}
              {/* Per-version Drive links — each version keeps its own, so
                  older versions still link correctly after later versions
                  are uploaded. */}
              <div className="mt-1.5 flex flex-wrap gap-x-3 gap-y-1">
                {v.driveFolderUrl && (
                  <a href={v.driveFolderUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    Folder ↗
                  </a>
                )}
                {v.driveUrl && (
                  <a href={v.driveUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    Source file ↗
                  </a>
                )}
                {v.googleDocUrl && (
                  <a href={v.googleDocUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    Google Doc ↗
                  </a>
                )}
                {v.reportHtmlUrl && (
                  <a href={v.reportHtmlUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    HTML report ↗
                  </a>
                )}
                {v.reportPdfUrl && (
                  <a href={v.reportPdfUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    PDF report ↗
                  </a>
                )}
                {!v.driveUrl && !v.googleDocUrl && !v.reportHtmlUrl && !v.reportPdfUrl && (
                  <span className="font-mono text-xs text-ink-faint">No Drive links yet for this version.</span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
VS_APPLY_EOF_vh5

echo ""
echo "Done. 6 files patched/updated:"
echo "  src/lib/types.ts                          (VersionDoc: added per-version Drive/Doc/report fields)"
echo "  src/lib/firebase/firestore.ts              (added updateVersionDrive)"
echo "  src/lib/report/googleDocsHandoff.ts        (now returns docId, not just docUrl)"
echo "  src/app/page.tsx                           (persists Drive links per-version, passes versionNumber down)"
echo "  src/components/review/ResultsView.tsx      (reuses existing Google Doc per version instead of duplicating; persists report links)"
echo "  src/components/library/MatterCard.tsx      (each version now shows its OWN Drive/Doc/report links)"
echo ""
echo "IMPORTANT — existing contracts/versions in Firestore won't have the new"
echo "fields until you upload a new version or use Google Docs/reports again on"
echo "them; old versions will just show 'No Drive links yet for this version'"
echo "in the Library until then. Nothing is deleted or broken for them."
echo ""
echo "Restart your dev server (Ctrl+C, then npm run dev) and try a fresh"
echo "upload end-to-end: Run Review → Open in Google Docs → Draft + add"
echo "redline comments → Download HTML/PDF → check the Library page for that"
echo "client and expand the matter's versions."
