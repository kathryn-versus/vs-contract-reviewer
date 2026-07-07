import { NextRequest, NextResponse } from 'next/server';
import { duplicateAsGoogleDoc } from '@/lib/drive/client';

// "Open in Google Docs" — duplicates the source contract file (already in
// Drive from the original upload) into a native Google Doc saved in the same
// matter folder, so the reviewer gets a fully editable copy of the whole
// contract rather than just the drafted redline excerpts.
export async function POST(req: NextRequest) {
  try {
    const { fileId, folderId, name } = await req.json();
    if (!fileId || !folderId) {
      return NextResponse.json({ error: 'fileId and folderId are required.' }, { status: 400 });
    }

    const { docId, docUrl } = await duplicateAsGoogleDoc({
      fileId,
      folderId,
      name: name || 'Contract copy',
    });

    return NextResponse.json({ docId, docUrl });
  } catch (err) {
    console.error('drive/duplicate-to-docs failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Could not duplicate into Google Docs.' },
      { status: 500 }
    );
  }
}

