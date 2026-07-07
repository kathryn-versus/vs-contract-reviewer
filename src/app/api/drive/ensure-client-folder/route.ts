import { NextRequest, NextResponse } from 'next/server';
import { ensureClientFolder } from '@/lib/drive/client';

// Creates (or finds) a client's top-level Drive folder — called right after
// a client is created, and again as a manual retry button on the client page
// for any older client that doesn't have one yet.
export async function POST(req: NextRequest) {
  try {
    const { clientName } = await req.json();
    if (!clientName) {
      return NextResponse.json({ error: 'clientName is required.' }, { status: 400 });
    }
    const { folderId, folderUrl } = await ensureClientFolder(clientName);
    return NextResponse.json({ folderId, folderUrl });
  } catch (err) {
    console.error('drive/ensure-client-folder failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Failed to create client Drive folder.' },
      { status: 500 }
    );
  }
}
