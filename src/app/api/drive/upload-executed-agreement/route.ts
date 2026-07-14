import { NextRequest, NextResponse } from 'next/server';
import { ensureClientFolder, ensureMatterFolder, ensureDocTypeFolder, uploadFileToFolder, getFolderLink } from '@/lib/drive/client';

// Uploads a fully executed/signed agreement — separate from the review
// pipeline's versions, since an executed copy (often countersigned
// externally, after negotiation) doesn't correspond to any single reviewed
// draft. Filed under Contract Reviews/{Client}/{Job Number — Project}/{Doc
// Type}/ when a project is given, alongside that job's review history —
// falls back to Contract Reviews/{Client}/{Doc Type}/ when no project is
// given, since an MSA is normally client-wide rather than tied to one job.
export async function POST(req: NextRequest) {
  try {
    const form = await req.formData();
    const file = form.get('file') as File | null;
    const clientName = form.get('clientName') as string | null;
    const docType = form.get('docType') as string | null;
    const label = (form.get('label') as string | null) ?? '';
    const projectNumber = (form.get('projectNumber') as string | null) || '';
    const projectName = (form.get('projectName') as string | null) || '';

    if (!file || !clientName || !docType) {
      return NextResponse.json({ error: 'file, clientName, and docType are required.' }, { status: 400 });
    }

    let targetFolderId: string;
    if (projectNumber && projectName) {
      const projectLabel = `${projectNumber} — ${projectName}`;
      const { matterFolderId } = await ensureMatterFolder(clientName, projectLabel);
      targetFolderId = await ensureDocTypeFolder(matterFolderId, docType);
    } else {
      const { folderId: clientFolderId } = await ensureClientFolder(clientName);
      targetFolderId = await ensureDocTypeFolder(clientFolderId, docType);
    }

    const buffer = Buffer.from(await file.arrayBuffer());

    const namePrefix = label ? `${docType} — ${label}` : docType;
    const { fileId, webViewLink } = await uploadFileToFolder({
      folderId: targetFolderId,
      fileName: `Executed — ${namePrefix} — ${file.name}`,
      mimeType: file.type || 'application/octet-stream',
      buffer,
    });
    const driveFolderUrl = await getFolderLink(targetFolderId);

    return NextResponse.json({ driveFileId: fileId, driveUrl: webViewLink, driveFolderUrl });
  } catch (err) {
    console.error('drive/upload-executed-agreement failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Upload failed.' },
      { status: 500 }
    );
  }
}
