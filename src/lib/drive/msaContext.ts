import 'server-only';
import { adminDb } from '@/lib/firebase/admin';
import { downloadFileBuffer } from './client';

const MAX_MSA_CHARS = 20_000;

/**
 * If the given client has a governing MSA on file (marked via Library →
 * matter → "Set as governing MSA"), pull its text straight from Drive so it
 * can be fed to Claude as context on this review — no manual re-entry of
 * standing positions required. Returns null (never throws) if there's no
 * governing MSA set, the file can't be found, or extraction fails — MSA
 * context is a nice-to-have and should never block a review.
 */
export async function getGoverningMsaContext(clientId: string): Promise<string | null> {
  try {
    const clientSnap = await adminDb().collection('clients').doc(clientId).get();
    if (!clientSnap.exists) return null;
    const msaContractId = clientSnap.data()?.msaContractId as string | null | undefined;
    if (!msaContractId) return null;

    const contractSnap = await adminDb().collection('contracts').doc(msaContractId).get();
    if (!contractSnap.exists) return null;
    const driveFileId = contractSnap.data()?.driveFileId as string | null | undefined;
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

