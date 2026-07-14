import { NextRequest, NextResponse } from 'next/server';
import { claude, CLAUDE_MODEL } from '@/lib/claude/client';
import { buildVersionDeltaPrompt } from '@/lib/claude/prompts';
import { downloadFileBuffer } from '@/lib/drive/client';
import { extractDocText } from '@/lib/drive/extractDocText';
import { adminDb } from '@/lib/firebase/admin';

// Fire-and-forget from the intake flow after a new version's Drive upload
// succeeds — compares it against the immediately-prior version's file and
// saves a short "what changed" summary onto that version's
// deltaFromPrevious field (already read by MatterCard and the review page,
// just never populated before now). Never throws back to the caller —
// worst case, deltaFromPrevious just stays null, same as today.
export async function POST(req: NextRequest) {
  try {
    const { contractId, versionId, previousDriveFileId, newDriveFileId } = await req.json();
    if (!contractId || !versionId || !previousDriveFileId || !newDriveFileId) {
      return NextResponse.json(
        { error: 'contractId, versionId, previousDriveFileId, and newDriveFileId are required.' },
        { status: 400 }
      );
    }

    const [prev, next] = await Promise.all([
      downloadFileBuffer(previousDriveFileId),
      downloadFileBuffer(newDriveFileId),
    ]);
    const [previousText, newText] = await Promise.all([
      extractDocText(prev.buffer, prev.mimeType, prev.name),
      extractDocText(next.buffer, next.mimeType, next.name),
    ]);

    if (!previousText || !newText) {
      // Can't extract one or both (e.g. a scanned PDF or a format we don't
      // parse) — nothing to compare, not an error.
      return NextResponse.json({ delta: null });
    }

    const prompt = buildVersionDeltaPrompt({ previousText, newText });
    const message = await claude().messages.create({
      model: CLAUDE_MODEL,
      max_tokens: 400,
      messages: [{ role: 'user', content: prompt }],
    });
    const textBlock = message.content.find((b) => b.type === 'text');
    const delta = textBlock && textBlock.type === 'text' ? textBlock.text.trim() : null;

    await adminDb()
      .collection('contracts')
      .doc(contractId)
      .collection('versions')
      .doc(versionId)
      .update({ deltaFromPrevious: delta });

    return NextResponse.json({ delta });
  } catch (err) {
    console.error('review/version-delta failed', err);
    return NextResponse.json({ delta: null, error: err instanceof Error ? err.message : 'Delta failed.' });
  }
}
