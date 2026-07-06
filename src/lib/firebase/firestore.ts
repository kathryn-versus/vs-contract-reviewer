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

export async function updateContractDrive(
  contractId: string,
  drive: { driveFileId: string; driveUrl: string; driveFolderUrl: string }
) {
  await updateDoc(doc(db, 'contracts', contractId), drive);
}

export async function moveContract(
  contractId: string,
  updates: Partial<Pick<ContractDoc, 'clientId' | 'clientName' | 'projectName'>>
) {
  await updateDoc(doc(db, 'contracts', contractId), updates);
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
