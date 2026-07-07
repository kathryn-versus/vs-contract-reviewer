import { NextRequest, NextResponse } from 'next/server';
import { addComment } from '@/lib/drive/client';

// Attaches drafted redlines to a Google Doc as comments. Google's Docs API
// has no way to create a real accept/reject "Suggestion" programmatically —
// confirmed against the current API reference, no request type exists for
// it — so this is the closest practical equivalent: one comment per
// finding, quoting the flagged language plus the suggested redline.
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const fileId: string | undefined = body.fileId;
    const items: { issueTitle: string; quote: string; redlineText: string }[] | undefined = body.items;

    if (!fileId || !items || items.length === 0) {
      return NextResponse.json({ error: 'fileId and at least one item are required.' }, { status: 400 });
    }

    let added = 0;
    for (const item of items) {
      const content = `${item.issueTitle}\n\nFlagged language: "${item.quote}"\n\nSuggested redline:\n${item.redlineText}`;
      await addComment(fileId, content);
      added++;
    }

    return NextResponse.json({ added });
  } catch (err) {
    console.error('drive/add-redline-comments failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Could not add comments to the Google Doc.' },
      { status: 500 }
    );
  }
}
