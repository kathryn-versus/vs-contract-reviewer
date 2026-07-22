import { NextRequest, NextResponse } from 'next/server';
import { ensureClientFolder, uploadFileToFolder } from '@/lib/drive/client';

// Uploads an MSA amendment straight to the client's Drive folder, alongside
// the MSA itself — same no-analysis, direct-upload pattern as
// /api/drive/upload-msa. Its text is pulled back out at review time by
// getGoverningMsaContext and folded into the MSA context given to Claude, so
// it's automatically considered on every future SOW review for this client.
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
      fileName: `MSA Amendment — ${file.name}`,
      mimeType: file.type || 'application/octet-stream',
      buffer,
    });

    return NextResponse.json({ fileId, webViewLink });
  } catch (err) {
    console.error('drive/upload-msa-amendment failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Amendment upload failed.' },
      { status: 500 }
    );
  }
}
