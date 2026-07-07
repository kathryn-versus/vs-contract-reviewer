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
