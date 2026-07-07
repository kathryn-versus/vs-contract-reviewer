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
