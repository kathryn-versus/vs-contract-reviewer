'use client';

/**
 * Sends drafted redlines to the Google Doc copy of a contract as comments —
 * see the note in src/lib/drive/client.ts's addComment for why these aren't
 * text-anchored to the flagged passage.
 */
export async function addRedlineCommentsToDoc(params: {
  fileId: string;
  items: { issueTitle: string; quote: string; redlineText: string }[];
}): Promise<{ added: number }> {
  const res = await fetch('/api/drive/add-redline-comments', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error);
  return data;
}
