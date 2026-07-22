import 'server-only';
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
            `--- AMENDMENT: ${amendment.fileName ?? name} ---\n${text.slice(0, MAX_AMENDMENT_CHARS)}`
          );
        }
      } catch (err) {
        console.error('getGoverningMsaContext: amendment extraction failed', err);
      }
    }

    if (!msaText && amendmentBlocks.length === 0) return null;
    return [msaText, ...amendmentBlocks].filter(Boolean).join('\n\n');
  } catch (err) {
    console.error('getGoverningMsaContext failed', err);
    return null;
  }
}
