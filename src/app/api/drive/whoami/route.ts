import { NextResponse } from 'next/server';
import { driveClient } from '@/lib/drive/client';

// Diagnostic only — safe to delete once Drive is confirmed working. Confirms
// which Google account the server's refresh token is actually authenticated
// as, to rule out the OAuth Playground consent having been granted under the
// wrong already-logged-in Google account instead of doco@vsnyc.tv.
export async function GET() {
  try {
    const drive = driveClient();
    const res = await drive.about.get({ fields: 'user' });
    return NextResponse.json({ authenticatedAs: res.data.user });
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : String(err) },
      { status: 500 }
    );
  }
}
