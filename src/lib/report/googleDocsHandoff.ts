// "Open in Google Docs" duplicates the full source contract (not just
// drafted redlines) into a native Google Doc saved in the matter's Drive
// folder, via /api/drive/duplicate-to-docs. Requires the contract to already
// have a driveFileId + driveFolderId (i.e. the Drive upload step succeeded).
export async function duplicateContractToGoogleDocs(params: {
  fileId: string;
  folderId: string;
  name: string;
}): Promise<{ docId: string; docUrl: string }> {
  const res = await fetch('/api/drive/duplicate-to-docs', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error);
  window.open(data.docUrl, '_blank', 'noopener,noreferrer');
  return { docId: data.docId, docUrl: data.docUrl };
}
