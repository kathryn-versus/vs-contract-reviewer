import 'server-only';
import { adminDb } from '@/lib/firebase/admin';
import { downloadFileBuffer } from './client';
import { extractDocText } from './extractDocText';

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
    const text = await extractDocText(buffer, mimeType, name);
    return text ? text.slice(0, MAX_MSA_CHARS) : null;
  } catch (err) {
    console.error('getGoverningMsaContext failed', err);
    return null;
  }
}

