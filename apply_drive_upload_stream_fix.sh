#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_drive_upload_stream_fix.sh
set -e

mkdir -p "$(dirname "src/lib/drive/client.ts")"
cat > "src/lib/drive/client.ts" << 'VS_APPLY_EOF_streamfix'
import 'server-only';
import { Readable } from 'stream';
import { google } from 'googleapis';

// All Drive operations run as doco@vsnyc.tv via OAuth 2.0, server-side only —
// the refresh token never reaches the browser. Brief §7.
function oauthClient() {
  const client = new google.auth.OAuth2(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    process.env.GOOGLE_REDIRECT_URI
  );
  client.setCredentials({ refresh_token: process.env.GOOGLE_DOCO_REFRESH_TOKEN });
  return client;
}

export function driveClient() {
  return google.drive({ version: 'v3', auth: oauthClient() });
}

export function gmailClient() {
  return google.gmail({ version: 'v1', auth: oauthClient() });
}

const ROOT_FOLDER_ID = process.env.DRIVE_ROOT_FOLDER_ID!;

// NOTE: every call below passes supportsAllDrives (and
// includeItemsFromAllDrives on list) — required for the Drive API to see or
// write to anything inside a Shared Drive ("Contributor" is a Shared Drive
// permission level, not a personal-folder one, so DRIVE_ROOT_FOLDER_ID living
// in a Shared Drive is why folder creation was 404ing with "File not found"
// even though the folder was genuinely shared).

async function findOrCreateFolder(name: string, parentId: string): Promise<string> {
  const drive = driveClient();
  const escaped = name.replace(/'/g, "\\'");
  const res = await drive.files.list({
    q: `'${parentId}' in parents and name = '${escaped}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false`,
    fields: 'files(id, name)',
    spaces: 'drive',
    supportsAllDrives: true,
    includeItemsFromAllDrives: true,
  });
  const existing = res.data.files?.[0];
  if (existing?.id) return existing.id;

  const created = await drive.files.create({
    requestBody: {
      name,
      mimeType: 'application/vnd.google-apps.folder',
      parents: [parentId],
    },
    fields: 'id',
    supportsAllDrives: true,
  });
  if (!created.data.id) throw new Error(`Failed to create Drive folder "${name}"`);
  return created.data.id;
}

/**
 * Ensures Contract Reviews/{Client}/{Project (Number)}/ exists and returns
 * that folder's id. Matches the folder structure in brief §7.
 */
export async function ensureMatterFolder(clientName: string, projectLabel: string): Promise<{
  clientFolderId: string;
  matterFolderId: string;
}> {
  const clientFolderId = await findOrCreateFolder(clientName, ROOT_FOLDER_ID);
  const matterFolderId = await findOrCreateFolder(projectLabel, clientFolderId);
  return { clientFolderId, matterFolderId };
}

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10); // YYYY-MM-DD
}

/**
 * Ensures a dated subfolder exists under a matter folder — Contract
 * Reviews/{Client}/{Project (Number)}/{YYYY-MM-DD}/ — so everything from one
 * review run (the uploaded source file, its Google Doc duplicate, and a copy
 * of the generated report) lands together instead of piling up flat in the
 * project folder. Reused as-is if a review already ran that day.
 */
export async function ensureDatedReviewFolder(matterFolderId: string, when: Date = new Date()): Promise<string> {
  return findOrCreateFolder(isoDate(when), matterFolderId);
}

export async function uploadFileToFolder(params: {
  folderId: string;
  fileName: string;
  mimeType: string;
  buffer: Buffer;
}): Promise<{ fileId: string; webViewLink: string }> {
  const drive = driveClient();

  // Readable is imported statically at the top of this file now — a dynamic
  // `await import('stream')` here previously came back with an odd shape
  // under Next's server bundling, so `Readable` was undefined and
  // `Readable.from(...)` threw "Cannot read properties of undefined
  // (reading 'from')" on every upload attempt.
  const res = await drive.files.create({
    requestBody: { name: params.fileName, parents: [params.folderId] },
    media: { mimeType: params.mimeType, body: Readable.from(params.buffer) },
    fields: 'id, webViewLink',
    supportsAllDrives: true,
  });

  if (!res.data.id) throw new Error('Drive upload did not return a file id.');
  return { fileId: res.data.id, webViewLink: res.data.webViewLink ?? '' };
}

export async function getFolderLink(folderId: string): Promise<string> {
  const drive = driveClient();
  const res = await drive.files.get({ fileId: folderId, fields: 'webViewLink', supportsAllDrives: true });
  return res.data.webViewLink ?? `https://drive.google.com/drive/folders/${folderId}`;
}

export async function renameFile(fileId: string, name: string) {
  const drive = driveClient();
  await drive.files.update({ fileId, requestBody: { name }, supportsAllDrives: true });
}

export async function moveFile(fileId: string, newParentId: string, oldParentId: string) {
  const drive = driveClient();
  await drive.files.update({
    fileId,
    addParents: newParentId,
    removeParents: oldParentId,
    supportsAllDrives: true,
  });
}

/**
 * Duplicates an uploaded contract into a native, fully-editable Google Doc
 * saved alongside the source file — Drive converts supported formats (DOCX
 * reliably; PDF conversion quality varies) on copy when a Google Workspace
 * mimeType is requested.
 */
export async function duplicateAsGoogleDoc(params: {
  fileId: string;
  folderId: string;
  name: string;
}): Promise<{ docId: string; docUrl: string }> {
  const drive = driveClient();
  const res = await drive.files.copy({
    fileId: params.fileId,
    requestBody: {
      name: params.name,
      mimeType: 'application/vnd.google-apps.document',
      parents: [params.folderId],
    },
    fields: 'id, webViewLink',
    supportsAllDrives: true,
  });
  if (!res.data.id) throw new Error('Drive did not return a copied document id.');
  return {
    docId: res.data.id,
    docUrl: res.data.webViewLink ?? `https://docs.google.com/document/d/${res.data.id}/edit`,
  };
}

/** Downloads a Drive file's raw bytes — used to pull MSA text for review context. */
export async function downloadFileBuffer(
  fileId: string
): Promise<{ buffer: Buffer; mimeType: string; name: string }> {
  const drive = driveClient();
  const meta = await drive.files.get({ fileId, fields: 'name, mimeType', supportsAllDrives: true });
  const res = await drive.files.get(
    { fileId, alt: 'media', supportsAllDrives: true },
    { responseType: 'arraybuffer' }
  );
  const buffer = Buffer.from(res.data as ArrayBuffer);
  return { buffer, mimeType: meta.data.mimeType ?? 'application/octet-stream', name: meta.data.name ?? 'file' };
}
VS_APPLY_EOF_streamfix

echo ""
echo "Done. 1 file updated: src/lib/drive/client.ts"
echo "Fixed: uploadFileToFolder now imports Readable statically instead of"
echo "via a dynamic import(), which is what was actually crashing every upload."
echo ""
echo "Restart your dev server (Ctrl+C, then npm run dev) and try uploading again."
echo "Once the file uploads successfully, the 'Open in Google Docs' button"
echo "should stop being grayed out too (it only unlocks once both driveFileId"
echo "and driveFolderId come back from a successful /api/drive/upload)."
