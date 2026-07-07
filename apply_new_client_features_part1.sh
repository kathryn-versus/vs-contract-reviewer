#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_new_client_features_part1.sh
#
# Part 1 of 2: data model, Firestore helpers, Drive client helpers, MSA
# context auto-pull, and two new Drive API routes.
set -e

# ── 1. src/lib/types.ts — new ClientDoc fields ──────────────────────────────
cat > "src/lib/types.ts" << 'VS_APPLY_EOF_types'
// Core data model — mirrors the Firestore schema in the project brief §6.

export type Role = 'admin' | 'reviewer';

export interface UserDoc {
  uid: string;
  email: string;
  name: string;
  role: Role;
  createdAt: number; // ms epoch
  lastLoginAt: number;
}

export interface ClientDoc {
  id: string;
  name: string;
  slug: string;
  notes: string;
  // Existing "governing MSA" flow — a fully-reviewed matter designated as
  // this client's MSA from the Library (Matter → "Set as governing MSA").
  msaContractId: string | null;
  // Drive folder for this client, created as soon as the client is added
  // (rather than lazily on first contract upload) so there's always
  // somewhere to open and drop files into right away.
  driveFolderId: string | null;
  driveFolderUrl: string | null;
  // Directly-uploaded MSA (Library → client page → "Upload MSA") — stored
  // straight to Drive with no Claude analysis, simpler than routing an MSA
  // through the full review pipeline just to designate it as governing.
  msaDriveFileId: string | null;
  msaDriveUrl: string | null;
  // Explicit "no MSA on file" flag, set from the client page — distinct from
  // simply having neither of the two MSA fields above set (which just means
  // "not yet addressed").
  noMsa: boolean;
  createdAt: number;
  createdBy: string;
}

export type DocType = 'MSA' | 'SOW' | 'MSA+SOW' | 'Other';

export interface SubmittedBy {
  uid: string;
  name: string;
  email: string;
}

export interface ContractDoc {
  id: string;
  clientId: string;
  clientName: string;
  projectName: string;
  projectNumber: string;
  docType: DocType;
  counterparty: string;
  submittedBy: SubmittedBy;
  driveFileId: string | null;
  driveUrl: string | null;
  driveFolderUrl: string | null;
  driveFolderId: string | null;
  createdAt: number;
  latestVersionId: string | null;
}

export type Severity = 'high' | 'medium' | 'low';

export interface Finding {
  uid: string;
  concernId: number;
  concernLabel: string;
  severity: Severity;
  issueTitle: string;
  quote: string;
  location: string;
  analysis: string;
  recommendation: string;
  // Set once a redline is drafted for this finding and persisted back to the
  // version doc — lets a past review be reopened with its drafted redlines
  // intact instead of needing them redrafted from scratch.
  redlineText?: string;
}

export interface VersionDoc {
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
}

export interface ThreadMessage {
  role: 'user' | 'assistant';
  content: string;
  timestamp: number;
}

export interface IssueThreadDoc {
  id: string;
  messages: ThreadMessage[];
}

// The standing concerns — brief §5, plus additions since. Count is not fixed
// at eight anymore, so nothing downstream should hardcode a number; use
// STANDING_CONCERNS.length wherever a count needs to be displayed.
export interface Concern {
  id: number;
  label: string;
  description: string;
}

export const STANDING_CONCERNS: Concern[] = [
  {
    id: 1,
    label: 'Mutual termination for convenience',
    description:
      'Both parties should be able to terminate for convenience, not just the client.',
  },
  {
    id: 2,
    label: 'Cure period before termination for cause',
    description:
      'Termination for cause should require notice and opportunity to cure. Watch for overly broad "cause" definitions.',
  },
  {
    id: 3,
    label: 'Narrow indemnification obligations',
    description:
      "Indemnity should be tied to actual fault — not cover the client's own acts or ordinary business risk.",
  },
  {
    id: 4,
    label: 'Liability cap applies to indemnification',
    description:
      "If there's a liability cap, indemnification shouldn't be carved out (or only narrow carve-outs like IP/confidentiality should survive).",
  },
  {
    id: 5,
    label: 'Permit normal use of freelancers/subcontractors',
    description:
      'Standard production use of freelancers shouldn\'t require case-by-case prior written approval.',
  },
  {
    id: 6,
    label: 'Relax AI restrictions',
    description:
      'Restrictions should target real risk (training on client IP, undisclosed AI deliverables) — not block ordinary AI tool use in the production workflow.',
  },
  {
    id: 7,
    label: 'Portfolio use and awards submissions',
    description:
      "After public release, portfolio use and awards submissions shouldn't require separate approval each time.",
  },
  {
    id: 8,
    label: 'Standard kill fee / cancellation fee',
    description:
      'SOWs should include a defined cancellation fee structure tied to notice period or production stage.',
  },
  {
    id: 9,
    label: 'Standard payment terms',
    description:
      "Versus's standard payment terms depend on production type. Post-production/post work: 1st payment 50% NET 5 upon award of the SOW; 2nd payment 50% NET 30 following receipt of deliverables. Live-action production (per standard AICP Payment Guidelines): first payment of 75% of the contract price, due upon signing of the contract but not later than 5 business days prior to the first shoot day — due whether or not a written contract/PO/letter of agreement is in hand, since a verbal order to commence production is enough to trigger it; second payment of 25% of the contract price (plus all additional approved and invoiced overages) due upon approval of dailies but not later than airing of the commercial or 30 days from the date of the final invoice, whichever is sooner — the firm-bid portion of a cost-plus job is paid on this schedule regardless of whether the cost-plus items have been actualized yet, and cost-plus invoices are separately due within 30 days of invoice. Determine which structure applies from the nature of the deliverables/scope described in the document (post/edit/sound/animation work vs. a live-action shoot), then flag any payment schedule that requires more up-front risk from Versus than these terms, defers payment materially longer, ties payment to a condition Versus doesn't control without a fallback deadline (e.g., an undefined 'client approval' with no outside date), or omits a clear payment schedule entirely.",
  },
];

// Condensed labels for the always-visible concern index strip (on-screen and
// in exported reports) — short enough to fit all of them on one line, unlike
// the full concern descriptions above.
export const CONCERN_SHORT_LABELS: Record<number, string> = {
  1: 'Mutual termination',
  2: 'Cure period',
  3: 'Indemnification scope',
  4: 'Cap applies to indemnity',
  5: 'Freelancers/subs',
  6: 'AI tool use',
  7: 'Portfolio/awards',
  8: 'Kill fee structure',
  9: 'Payment terms',
};

export const SEVERITY_LABELS: Record<Severity, string> = {
  high: 'Significantly one-sided or high financial/legal exposure — must negotiate',
  medium: 'Notable but not severe, or partially addressed — should negotiate',
  low: 'Minor wording issue or low practical risk — nice to have',
};
VS_APPLY_EOF_types
echo "Wrote src/lib/types.ts"

# ── 2. src/lib/firebase/firestore.ts — new client helpers ───────────────────
cat > "src/lib/firebase/firestore.ts" << 'VS_APPLY_EOF_firestore'
'use client';

import {
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
    driveFolderId: null,
    driveFolderUrl: null,
    msaDriveFileId: null,
    msaDriveUrl: null,
    noMsa: false,
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

export async function updateClientDrive(clientId: string, drive: { driveFolderId: string; driveFolderUrl: string }) {
  await updateDoc(doc(db, 'clients', clientId), drive);
}

/**
 * Ensures a client has a Drive folder, creating one (via the server-side
 * Drive API route) if it doesn't already have one on file, and persisting
 * the result. Idempotent — safe to call on every client, old or new; clients
 * that already have a folder just get returned unchanged.
 */
export async function ensureClientDriveFolder(client: ClientDoc): Promise<ClientDoc> {
  if (client.driveFolderId && client.driveFolderUrl) return client;
  try {
    const res = await fetch('/api/drive/ensure-client-folder', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ clientName: client.name }),
    });
    const data = await res.json();
    if (data.error) return client;
    await updateClientDrive(client.id, { driveFolderId: data.folderId, driveFolderUrl: data.folderUrl });
    return { ...client, driveFolderId: data.folderId, driveFolderUrl: data.folderUrl };
  } catch {
    // Non-fatal — the client page shows a "Create Drive folder" retry button
    // whenever driveFolderUrl is still missing.
    return client;
  }
}

// Directly-uploaded MSA (no Claude analysis) — see ClientDetailView's
// "Governing MSA" section. Setting a file clears noMsa (mutually exclusive),
// and vice versa.
export async function setClientMsaFile(clientId: string, msa: { msaDriveFileId: string; msaDriveUrl: string }) {
  await updateDoc(doc(db, 'clients', clientId), { ...msa, noMsa: false });
}

export async function clearClientMsaFile(clientId: string) {
  await updateDoc(doc(db, 'clients', clientId), { msaDriveFileId: null, msaDriveUrl: null });
}

export async function setClientNoMsa(clientId: string, noMsa: boolean) {
  await updateDoc(
    doc(db, 'clients', clientId),
    noMsa ? { noMsa: true, msaDriveFileId: null, msaDriveUrl: null } : { noMsa: false }
  );
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

/**
 * Finds every version, across every contract, uploaded with this exact file
 * name — used by the intake form to warn a reviewer before they accidentally
 * re-review a contract that's already on file. A collectionGroup query, so
 * it searches every contract's versions subcollection at once rather than
 * needing to know which contract to look in ahead of time.
 */
export async function findContractsByFileName(
  fileName: string
): Promise<{ contractId: string; version: VersionDoc }[]> {
  const snap = await getDocs(query(collectionGroup(db, 'versions'), where('fileName', '==', fileName)));
  return snap.docs
    .filter((d) => d.ref.parent.parent)
    .map((d) => ({
      contractId: d.ref.parent.parent!.id,
      version: { id: d.id, ...(d.data() as Omit<VersionDoc, 'id'>), uploadedAt: toMillis(d.data().uploadedAt) },
    }));
}

export async function getContract(contractId: string): Promise<ContractDoc | null> {
  const snap = await getDoc(doc(db, 'contracts', contractId));
  if (!snap.exists()) return null;
  return { id: snap.id, ...(snap.data() as Omit<ContractDoc, 'id'>), createdAt: toMillis(snap.data().createdAt) };
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

export async function getVersion(contractId: string, versionId: string): Promise<VersionDoc | null> {
  const snap = await getDoc(doc(db, 'contracts', contractId, 'versions', versionId));
  if (!snap.exists()) return null;
  return { id: snap.id, ...(snap.data() as Omit<VersionDoc, 'id'>), uploadedAt: toMillis(snap.data().uploadedAt) };
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

/**
 * Persists the findings array (with any drafted redlineText merged in) back
 * to the version doc, so reopening this version's results later shows
 * previously-drafted redlines instead of needing them redrafted.
 */
export async function updateVersionFindings(contractId: string, versionId: string, findings: Finding[]) {
  await updateDoc(doc(db, 'contracts', contractId, 'versions', versionId), { findings });
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
VS_APPLY_EOF_firestore
echo "Wrote src/lib/firebase/firestore.ts"

# ── 3. src/lib/drive/client.ts — add ensureClientFolder ─────────────────────
cat > "src/lib/drive/client.ts" << 'VS_APPLY_EOF_driveclient'
import 'server-only';
import { Readable } from 'stream';
import { google } from 'googleapis';

// All Drive operations run as doco@vsnyc.tv via OAuth 2.0, server-side only —
// the refresh token never reaches the browser. Brief §7.
function oauthClient() {
  const client = new google.auth.OAuth2(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    process.env.GOOGLE_REDIRECT_URI
  );
  client.setCredentials({ refresh_token: process.env.GOOGLE_DOCO_REFRESH_TOKEN });
  return client;
}

export function driveClient() {
  return google.drive({ version: 'v3', auth: oauthClient() });
}

export function gmailClient() {
  return google.gmail({ version: 'v1', auth: oauthClient() });
}

const ROOT_FOLDER_ID = process.env.DRIVE_ROOT_FOLDER_ID!;

// NOTE: every call below passes supportsAllDrives (and
// includeItemsFromAllDrives on list) — required for the Drive API to see or
// write to anything inside a Shared Drive ("Contributor" is a Shared Drive
// permission level, not a personal-folder one, so DRIVE_ROOT_FOLDER_ID living
// in a Shared Drive is why folder creation was 404ing with "File not found"
// even though the folder was genuinely shared).

async function findOrCreateFolder(name: string, parentId: string): Promise<string> {
  const drive = driveClient();
  const escaped = name.replace(/'/g, "\\'");
  const res = await drive.files.list({
    q: `'${parentId}' in parents and name = '${escaped}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false`,
    fields: 'files(id, name)',
    spaces: 'drive',
    supportsAllDrives: true,
    includeItemsFromAllDrives: true,
  });
  const existing = res.data.files?.[0];
  if (existing?.id) return existing.id;

  const created = await drive.files.create({
    requestBody: {
      name,
      mimeType: 'application/vnd.google-apps.folder',
      parents: [parentId],
    },
    fields: 'id',
    supportsAllDrives: true,
  });
  if (!created.data.id) throw new Error(`Failed to create Drive folder "${name}"`);
  return created.data.id;
}

/**
 * Ensures Contract Reviews/{Client}/{Job Number — Project}/ exists and
 * returns that folder's id. Matches the folder structure in brief §7.
 */
export async function ensureMatterFolder(clientName: string, projectLabel: string): Promise<{
  clientFolderId: string;
  matterFolderId: string;
}> {
  const clientFolderId = await findOrCreateFolder(clientName, ROOT_FOLDER_ID);
  const matterFolderId = await findOrCreateFolder(projectLabel, clientFolderId);
  return { clientFolderId, matterFolderId };
}

/**
 * Ensures a top-level client folder exists (Contract Reviews/{Client}/) and
 * returns its id + a link to it. Used to create a client's Drive folder as
 * soon as the client is added, rather than only lazily via
 * ensureMatterFolder on their first contract upload.
 */
export async function ensureClientFolder(clientName: string): Promise<{ folderId: string; folderUrl: string }> {
  const folderId = await findOrCreateFolder(clientName, ROOT_FOLDER_ID);
  const folderUrl = await getFolderLink(folderId);
  return { folderId, folderUrl };
}

function folderTimestamp(d: Date): string {
  // YYYY-MM-DD HHhMMm, local time. Kept in 24-hour, zero-padded form so
  // folder names still sort correctly in Drive's alphabetical listing — a
  // 12-hour AM/PM format sorts wrong across the noon boundary (e.g.
  // "9:05am" would alphabetically land after "2:32pm" as plain text). The
  // "h"/"m" letters are just there so it visibly reads as a time instead of
  // looking like an arbitrary numeric code.
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}h${pad(d.getMinutes())}m`;
}

/**
 * Ensures a timestamped subfolder (down to the second) exists under a matter
 * folder, so every review run — the uploaded source file, its Google Doc
 * duplicate, and a copy of the generated report — gets its own folder
 * instead of multiple same-day runs piling into one shared date folder.
 * Makes the most recent run obvious at a glance in Drive's default
 * alphabetical sort.
 */
export async function ensureDatedReviewFolder(matterFolderId: string, when: Date = new Date()): Promise<string> {
  return findOrCreateFolder(folderTimestamp(when), matterFolderId);
}

export async function uploadFileToFolder(params: {
  folderId: string;
  fileName: string;
  mimeType: string;
  buffer: Buffer;
}): Promise<{ fileId: string; webViewLink: string }> {
  const drive = driveClient();

  // Readable is imported statically at the top of this file — a dynamic
  // `await import('stream')` here previously came back with an odd shape
  // under Next's server bundling, so `Readable` was undefined and
  // `Readable.from(...)` threw "Cannot read properties of undefined
  // (reading 'from')" on every upload attempt.
  const res = await drive.files.create({
    requestBody: { name: params.fileName, parents: [params.folderId] },
    media: { mimeType: params.mimeType, body: Readable.from(params.buffer) },
    fields: 'id, webViewLink',
    supportsAllDrives: true,
  });

  if (!res.data.id) throw new Error('Drive upload did not return a file id.');
  return { fileId: res.data.id, webViewLink: res.data.webViewLink ?? '' };
}

export async function getFolderLink(folderId: string): Promise<string> {
  const drive = driveClient();
  const res = await drive.files.get({ fileId: folderId, fields: 'webViewLink', supportsAllDrives: true });
  return res.data.webViewLink ?? `https://drive.google.com/drive/folders/${folderId}`;
}

export async function renameFile(fileId: string, name: string) {
  const drive = driveClient();
  await drive.files.update({ fileId, requestBody: { name }, supportsAllDrives: true });
}

export async function moveFile(fileId: string, newParentId: string, oldParentId: string) {
  const drive = driveClient();
  await drive.files.update({
    fileId,
    addParents: newParentId,
    removeParents: oldParentId,
    supportsAllDrives: true,
  });
}

/**
 * Duplicates an uploaded contract into a native, fully-editable Google Doc
 * saved alongside the source file — Drive converts supported formats (DOCX
 * reliably; PDF conversion quality varies) on copy when a Google Workspace
 * mimeType is requested.
 */
export async function duplicateAsGoogleDoc(params: {
  fileId: string;
  folderId: string;
  name: string;
}): Promise<{ docId: string; docUrl: string }> {
  const drive = driveClient();
  const res = await drive.files.copy({
    fileId: params.fileId,
    requestBody: {
      name: params.name,
      mimeType: 'application/vnd.google-apps.document',
      parents: [params.folderId],
    },
    fields: 'id, webViewLink',
    supportsAllDrives: true,
  });
  if (!res.data.id) throw new Error('Drive did not return a copied document id.');
  return {
    docId: res.data.id,
    docUrl: res.data.webViewLink ?? `https://docs.google.com/document/d/${res.data.id}/edit`,
  };
}

/** Downloads a Drive file's raw bytes — used to pull MSA text for review context. */
export async function downloadFileBuffer(
  fileId: string
): Promise<{ buffer: Buffer; mimeType: string; name: string }> {
  const drive = driveClient();
  const meta = await drive.files.get({ fileId, fields: 'name, mimeType', supportsAllDrives: true });
  const res = await drive.files.get(
    { fileId, alt: 'media', supportsAllDrives: true },
    { responseType: 'arraybuffer' }
  );
  const buffer = Buffer.from(res.data as ArrayBuffer);
  return { buffer, mimeType: meta.data.mimeType ?? 'application/octet-stream', name: meta.data.name ?? 'file' };
}

/**
 * Adds a comment to a Drive file — used to attach drafted redline language to
 * the Google Doc copy of a contract. Not text-anchored: Google's Docs API/UI
 * silently ignores anchor data on Workspace editor files (confirmed platform
 * limitation, not something fixable from our side), so these land as general
 * document-level comments in the comment sidebar rather than highlighting the
 * exact flagged passage. Each comment's content includes the quoted contract
 * language so it's still easy to locate manually.
 */
export async function addComment(fileId: string, content: string): Promise<void> {
  const drive = driveClient();
  await drive.comments.create({
    fileId,
    requestBody: { content },
    fields: 'id',
  });
}
VS_APPLY_EOF_driveclient
echo "Wrote src/lib/drive/client.ts"

# ── 4. src/lib/drive/msaContext.ts — prefer direct-upload MSA file ──────────
cat > "src/lib/drive/msaContext.ts" << 'VS_APPLY_EOF_msacontext'
import 'server-only';
import { adminDb } from '@/lib/firebase/admin';
import { downloadFileBuffer } from './client';

const MAX_MSA_CHARS = 20_000;

/**
 * Pulls this client's governing MSA text from Drive so it can be fed to
 * Claude as context on a review — no manual re-entry of standing positions
 * required. Checks two sources, in order:
 *   1. A directly-uploaded MSA file (Library → client page → "Upload MSA") —
 *      the simpler, no-analysis path.
 *   2. A fully-reviewed matter designated as governing MSA (Library →
 *      matter → "Set as governing MSA") — the original flow.
 * Returns null (never throws) if neither is set, the file can't be found, or
 * extraction fails — MSA context is a nice-to-have and should never block a
 * review.
 */
export async function getGoverningMsaContext(clientId: string): Promise<string | null> {
  try {
    const clientSnap = await adminDb().collection('clients').doc(clientId).get();
    if (!clientSnap.exists) return null;
    const clientData = clientSnap.data();

    let driveFileId = clientData?.msaDriveFileId as string | null | undefined;

    if (!driveFileId) {
      const msaContractId = clientData?.msaContractId as string | null | undefined;
      if (!msaContractId) return null;

      const contractSnap = await adminDb().collection('contracts').doc(msaContractId).get();
      if (!contractSnap.exists) return null;
      driveFileId = contractSnap.data()?.driveFileId as string | null | undefined;
    }
    if (!driveFileId) return null;

    const { buffer, mimeType, name } = await downloadFileBuffer(driveFileId);
    const text = await extractText(buffer, mimeType, name);
    return text ? text.slice(0, MAX_MSA_CHARS) : null;
  } catch (err) {
    console.error('getGoverningMsaContext failed', err);
    return null;
  }
}

async function extractText(buffer: Buffer, mimeType: string, name: string): Promise<string | null> {
  const lower = name.toLowerCase();

  if (lower.endsWith('.pdf') || mimeType.includes('pdf')) {
    const pdfParse = (await import('pdf-parse')).default;
    const result = await pdfParse(buffer);
    return result.text;
  }

  if (lower.endsWith('.docx') || mimeType.includes('officedocument.wordprocessingml')) {
    const mammoth = await import('mammoth');
    const result = await mammoth.extractRawText({ buffer });
    return result.value;
  }

  if (lower.endsWith('.txt') || mimeType.startsWith('text/')) {
    return buffer.toString('utf-8');
  }

  // Native Google Docs (e.g. a duplicated copy) aren't binary-downloadable via
  // alt=media in a plain-text-friendly way here — skip rather than error.
  return null;
}
VS_APPLY_EOF_msacontext
echo "Wrote src/lib/drive/msaContext.ts"

# ── 5. New route: ensure a client's Drive folder exists ─────────────────────
mkdir -p "src/app/api/drive/ensure-client-folder"
cat > "src/app/api/drive/ensure-client-folder/route.ts" << 'VS_APPLY_EOF_ensureroute'
import { NextRequest, NextResponse } from 'next/server';
import { ensureClientFolder } from '@/lib/drive/client';

// Creates (or finds) a client's top-level Drive folder — called right after
// a client is created, and again as a manual retry button on the client page
// for any older client that doesn't have one yet.
export async function POST(req: NextRequest) {
  try {
    const { clientName } = await req.json();
    if (!clientName) {
      return NextResponse.json({ error: 'clientName is required.' }, { status: 400 });
    }
    const { folderId, folderUrl } = await ensureClientFolder(clientName);
    return NextResponse.json({ folderId, folderUrl });
  } catch (err) {
    console.error('drive/ensure-client-folder failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Failed to create client Drive folder.' },
      { status: 500 }
    );
  }
}
VS_APPLY_EOF_ensureroute
echo "Wrote src/app/api/drive/ensure-client-folder/route.ts"

# ── 6. New route: upload an MSA file directly (no analysis) ─────────────────
mkdir -p "src/app/api/drive/upload-msa"
cat > "src/app/api/drive/upload-msa/route.ts" << 'VS_APPLY_EOF_msauploadroute'
import { NextRequest, NextResponse } from 'next/server';
import { ensureClientFolder, uploadFileToFolder } from '@/lib/drive/client';

// Uploads an MSA straight to the client's Drive folder with no Claude
// analysis — the simpler counterpart to running an MSA through the full
// review pipeline just to designate it as governing.
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
      fileName: `MSA — ${file.name}`,
      mimeType: file.type || 'application/octet-stream',
      buffer,
    });

    return NextResponse.json({ msaDriveFileId: fileId, msaDriveUrl: webViewLink });
  } catch (err) {
    console.error('drive/upload-msa failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'MSA upload failed.' },
      { status: 500 }
    );
  }
}
VS_APPLY_EOF_msauploadroute
echo "Wrote src/app/api/drive/upload-msa/route.ts"

echo ""
echo "Part 1 done. Now run apply_new_client_features_part2.sh."
