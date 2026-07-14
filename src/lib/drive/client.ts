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
 * Ensures Contract Reviews/{Client}/{Job Number — Project}/ exists and
 * returns that folder's id. Matches the folder structure in brief §7.
 */
export async function ensureMatterFolder(clientName: string, projectLabel: string): Promise<{
  clientFolderId: string;
  matterFolderId: string;
}> {
  const clientFolderId = await findOrCreateFolder(clientName, ROOT_FOLDER_ID);
  const matterFolderId = await findOrCreateFolder(projectLabel, clientFolderId);
  return { clientFolderId, matterFolderId };
}

/**
 * Ensures a top-level client folder exists (Contract Reviews/{Client}/) and
 * returns its id + a link to it. Used to create a client's Drive folder as
 * soon as the client is added, rather than only lazily via
 * ensureMatterFolder on their first contract upload.
 */
export async function ensureClientFolder(clientName: string): Promise<{ folderId: string; folderUrl: string }> {
  const folderId = await findOrCreateFolder(clientName, ROOT_FOLDER_ID);
  const folderUrl = await getFolderLink(folderId);
  return { folderId, folderUrl };
}

function folderTimestamp(d: Date): string {
  // YYYY-MM-DD HHhMMm, always in America/New_York regardless of the
  // server's own clock. Firebase App Hosting runs the Node process in UTC,
  // so without this, folder names would be ~4-5 hours ahead of actual NYC
  // time (and near midnight could even land on the wrong calendar date
  // entirely — e.g. an 11:54 PM upload getting stamped as 03h54m the NEXT
  // day). Intl.DateTimeFormat handles the EST/EDT daylight-saving switch
  // automatically, so this doesn't need manual offset math. Kept in
  // 24-hour, zero-padded form so folder names still sort correctly in
  // Drive's alphabetical listing — a 12-hour AM/PM format sorts wrong
  // across the noon boundary (e.g. "9:05am" would alphabetically land
  // after "2:32pm" as plain text). The "h"/"m" letters are just there so it
  // visibly reads as a time instead of looking like an arbitrary numeric
  // code.
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/New_York',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(d);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '00';
  // Some environments return "24" for midnight under hour12: false instead
  // of "00" — normalize just in case.
  const hour = get('hour') === '24' ? '00' : get('hour');
  return `${get('year')}-${get('month')}-${get('day')} ${hour}h${get('minute')}m`;
}

/**
 * Ensures a timestamped subfolder (down to the second) exists under a matter
 * folder, so every review run — the uploaded source file, its Google Doc
 * duplicate, and a copy of the generated report — gets its own folder
 * instead of multiple same-day runs piling into one shared date folder.
 * Makes the most recent run obvious at a glance in Drive's default
 * alphabetical sort.
 */
export async function ensureDatedReviewFolder(matterFolderId: string, when: Date = new Date()): Promise<string> {
  return findOrCreateFolder(folderTimestamp(when), matterFolderId);
}

/**
 * Ensures a document-type subfolder (MSA / SOW / Change Order / etc.) exists
 * directly under a Job's matter folder — Contract Reviews/{Client}/{Job
 * Number — Project}/{Doc Type}/ — so multiple different documents filed
 * under the same job (an MSA, a SOW, several Change Orders) land in their
 * own clearly separated space instead of one flat timestamped list where
 * it's not obvious what's what. Dated review-run folders then nest one
 * level further inside this, per upload.
 */
export async function ensureDocTypeFolder(matterFolderId: string, docType: string): Promise<string> {
  return findOrCreateFolder(docType, matterFolderId);
}

export async function uploadFileToFolder(params: {
  folderId: string;
  fileName: string;
  mimeType: string;
  buffer: Buffer;
}): Promise<{ fileId: string; webViewLink: string }> {
  const drive = driveClient();

  // Readable is imported statically at the top of this file — a dynamic
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

/**
 * Adds a comment to a Drive file — used to attach drafted redline language to
 * the Google Doc copy of a contract. Not text-anchored: Google's Docs API/UI
 * silently ignores anchor data on Workspace editor files (confirmed platform
 * limitation, not something fixable from our side), so these land as general
 * document-level comments in the comment sidebar rather than highlighting the
 * exact flagged passage. Each comment's content includes the quoted contract
 * language so it's still easy to locate manually.
 */
export async function addComment(fileId: string, content: string): Promise<void> {
  const drive = driveClient();
  await drive.comments.create({
    fileId,
    requestBody: { content },
    fields: 'id',
  });
}
