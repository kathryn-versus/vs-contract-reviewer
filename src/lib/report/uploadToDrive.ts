'use client';

/**
 * Uploads a copy of a generated report (HTML or PDF blob) into the Drive
 * folder for this review — the same dated folder the source contract and
 * any Google Doc duplicate already live in.
 */
export async function uploadReportToDrive(params: {
  blob: Blob;
  filename: string;
  folderId: string;
}): Promise<{ driveFileId: string; driveUrl: string }> {
  const form = new FormData();
  form.append('file', params.blob, params.filename);
  form.append('folderId', params.folderId);

  const res = await fetch('/api/drive/upload-report', { method: 'POST', body: form });
  const data = await res.json();
  if (data.error) throw new Error(data.error);
  return data;
}
