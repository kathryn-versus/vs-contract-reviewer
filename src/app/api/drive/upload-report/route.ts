import { NextRequest, NextResponse } from 'next/server';
import { uploadFileToFolder } from '@/lib/drive/client';

// Uploads a copy of the generated HTML/PDF report into the same dated Drive
// folder as the source contract for this review (folderId comes from the
// driveFolderId returned by /api/drive/upload for this version). Fire-and-
// forget from the client — a failure here shouldn't block anyone from
// downloading their report locally.
export async function POST(req: NextRequest) {
  try {
    const form = await req.formData();
    const file = form.get('file') as File | null;
    const folderId = form.get('folderId') as string | null;

    if (!file || !folderId) {
      return NextResponse.json({ error: 'file and folderId are required.' }, { status: 400 });
    }

    const buffer = Buffer.from(await file.arrayBuffer());
    const { fileId, webViewLink } = await uploadFileToFolder({
      folderId,
      fileName: file.name,
      mimeType: file.type || 'application/octet-stream',
      buffer,
    });

    return NextResponse.json({ driveFileId: fileId, driveUrl: webViewLink });
  } catch (err) {
    console.error('drive/upload-report failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Report upload failed.' },
      { status: 500 }
    );
  }
}
