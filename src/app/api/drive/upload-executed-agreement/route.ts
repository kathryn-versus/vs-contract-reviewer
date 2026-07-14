import { NextRequest, NextResponse } from 'next/server';
import { ensureClientFolder, uploadFileToFolder } from '@/lib/drive/client';

// Uploads a fully executed/signed agreement straight to the client's Drive
// folder, labeled by document type — separate from the review pipeline's
// versions, since an executed copy (often countersigned externally, after
// negotiation) doesn't correspond to any single reviewed draft. Multiple can
// exist per client (e.g. an MSA plus several Change Orders over time).
export async function POST(req: NextRequest) {
  try {
    const form = await req.formData();
    const file = form.get('file') as File | null;
    const clientName = form.get('clientName') as string | null;
    const docType = form.get('docType') as string | null;
    const label = (form.get('label') as string | null) ?? '';

    if (!file || !clientName || !docType) {
      return NextResponse.json({ error: 'file, clientName, and docType are required.' }, { status: 400 });
    }

    const { folderId } = await ensureClientFolder(clientName);
    const buffer = Buffer.from(await file.arrayBuffer());

    const namePrefix = label ? `${docType} — ${label}` : docType;
    const { fileId, webViewLink } = await uploadFileToFolder({
      folderId,
      fileName: `Executed — ${namePrefix} — ${file.name}`,
      mimeType: file.type || 'application/octet-stream',
      buffer,
    });

    return NextResponse.json({ driveFileId: fileId, driveUrl: webViewLink });
  } catch (err) {
    console.error('drive/upload-executed-agreement failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Upload failed.' },
      { status: 500 }
    );
  }
}
