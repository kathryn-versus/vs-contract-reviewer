import { NextRequest, NextResponse } from 'next/server';
import { ensureMatterFolder, moveFile, renameFile } from '@/lib/drive/client';

// Used by Library → "Folder Reorganization": reassign a matter to a
// different client, rename the project, or move between projects. Renames
// and/or moves the Drive folder tree via the Drive API. Brief §4.2 / §7.
export async function POST(req: NextRequest) {
  try {
    const { fileId, oldFolderId, newClientName, newProjectLabel, newFileName } = await req.json();

    if (!fileId || !oldFolderId) {
      return NextResponse.json({ error: 'fileId and oldFolderId are required.' }, { status: 400 });
    }

    if (newFileName) {
      await renameFile(fileId, newFileName);
    }

    if (newClientName && newProjectLabel) {
      const { matterFolderId } = await ensureMatterFolder(newClientName, newProjectLabel);
      await moveFile(fileId, matterFolderId, oldFolderId);
      return NextResponse.json({ newFolderId: matterFolderId });
    }

    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error('drive/rename failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Drive folder update failed.' },
      { status: 500 }
    );
  }
}
