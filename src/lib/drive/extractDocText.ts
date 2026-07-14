import 'server-only';

/**
 * Extracts plain text from a downloaded Drive file's raw bytes, based on
 * file extension/mimeType. Shared by anything that needs a Drive file's
 * text server-side (MSA context, version-to-version diffing) — returns null
 * (never throws) for unsupported formats like native Google Docs, since
 * callers treat missing text as "nothing to compare/pull" rather than a
 * hard failure.
 */
export async function extractDocText(buffer: Buffer, mimeType: string, name: string): Promise<string | null> {
  const lower = name.toLowerCase();

  if (lower.endsWith('.pdf') || mimeType.includes('pdf')) {
    const pdfParse = (await import('pdf-parse')).default;
    const result = await pdfParse(buffer);
    return result.text;
  }

  if (lower.endsWith('.docx') || mimeType.includes('officedocument.wordprocessingml')) {
    const mammoth = await import('mammoth');
    const result = await mammoth.extractRawText({ buffer });
    return result.value;
  }

  if (lower.endsWith('.txt') || mimeType.startsWith('text/')) {
    return buffer.toString('utf-8');
  }

  return null;
}
