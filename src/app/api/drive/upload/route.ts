import { NextRequest, NextResponse } from 'next/server';
import { ensureMatterFolder, ensureDatedReviewFolder, uploadFileToFolder, getFolderLink } from '@/lib/drive/client';

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
    // Nest this review's files under a dated subfolder — Contract
    // Reviews/{Client}/{Job Number — Project}/{YYYY-MM-DD}/ — so the source
    // file, its Google Doc duplicate, and the report copy all land together.
    const dateFolderId = await ensureDatedReviewFolder(matterFolderId);

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
