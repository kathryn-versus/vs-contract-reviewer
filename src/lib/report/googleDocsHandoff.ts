// brief §4.1 "Google Docs Handoff": encode redline content into a
// docs.google.com/document/create URL; for long content, fall back to
// clipboard copy + open a blank doc with instructions.

const URL_LENGTH_SAFE_LIMIT = 1800; // conservative — browsers cap ~2000 chars for GET URLs

export async function openInGoogleDocs(title: string, body: string) {
  const encoded = `https://docs.google.com/document/create?title=${encodeURIComponent(title)}&body=${encodeURIComponent(body)}`;

  if (encoded.length <= URL_LENGTH_SAFE_LIMIT) {
    window.open(encoded, '_blank', 'noopener,noreferrer');
    return { mode: 'url' as const };
  }

  await navigator.clipboard.writeText(body);
  window.open('https://docs.google.com/document/create', '_blank', 'noopener,noreferrer');
  return { mode: 'clipboard' as const };
}
