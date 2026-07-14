import { NextRequest, NextResponse } from 'next/server';
import { ensureMatterFolder, ensureDocTypeFolder, ensureDatedReviewFolder, uploadFileToFolder, getFolderLink } from '@/lib/drive/client';

// Server-side only (brief §7: "All Drive API calls go through Next.js API
// routes — never direct from browser"). Accepts multipart form data with the
// original file plus client/project metadata, and returns Drive links to
// store on the contract/version Firestore docs.
export async function POST(req: NextRequest) {
  try {
    const form = await req.formData();
    const file = form.get('file') as File | null;
    const clientName = form.get('clientName') as string | null;
    const projectName = form.get('projectName') as string | null;
    const projectNumber = form.get('projectNumber') as string | null;
    const versionSuffix = (form.get('versionSuffix') as string | null) ?? '';
    const docType = (form.get('docType') as string | null) ?? null;

    if (!file || !clientName || !projectName || !projectNumber) {
      return NextResponse.json(
        { error: 'file, clientName, projectName, and projectNumber are required.' },
        { status: 400 }
      );
    }

    // Job Number first, then Project Name (e.g. "VS26153 — Eversana DSE
    // Animation") — matches how the studio refers to jobs internally.
    const projectLabel = `${projectNumber} — ${projectName}`;
    const { matterFolderId } = await ensureMatterFolder(clientName, projectLabel);
    // Nest under a doc-type subfolder first — Contract Reviews/{Client}/{Job
    // Number — Project}/{Doc Type}/ — so an MSA, a SOW, and however many
    // Change Orders end up filed under the same job land in clearly
    // separated folders rather than one undifferentiated pile. Falls back
    // to the matter folder itself if no docType was sent (keeps this route
    // working for any caller that hasn't been updated to send one yet).
    const docTypeFolderId = docType ? await ensureDocTypeFolder(matterFolderId, docType) : matterFolderId;
    // Then nest THIS review's files under a dated subfolder — .../{Doc
    // Type}/{YYYY-MM-DD HHhMMm}/ — so the source file, its Google Doc
    // duplicate, and the report copy all land together per upload.
    const dateFolderId = await ensureDatedReviewFolder(docTypeFolderId);

    const buffer = Buffer.from(await file.arrayBuffer());
    const fileName = versionSuffix ? appendSuffix(file.name, versionSuffix) : file.name;

    const { fileId, webViewLink } = await uploadFileToFolder({
      folderId: dateFolderId,
      fileName,
      mimeType: file.type || 'application/octet-stream',
      buffer,
    });

    const driveFolderUrl = await getFolderLink(dateFolderId);

    return NextResponse.json({
      driveFileId: fileId,
      driveUrl: webViewLink,
      driveFolderUrl,
      driveFolderId: dateFolderId,
    });
  } catch (err) {
    console.error('drive/upload failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Drive upload failed.' },
      { status: 500 }
    );
  }
}

function appendSuffix(fileName: string, suffix: string) {
  const dot = fileName.lastIndexOf('.');
  if (dot === -1) return `${fileName} ${suffix}`;
  return `${fileName.slice(0, dot)} ${suffix}${fileName.slice(dot)}`;
}
